// Thin Google Drive REST v3 client. This is the web equivalent of
// SyncFolderManager.swift: the rest of the app only ever calls `ensureSyncFolder`,
// `readJSONFile`/`writeJSONFile`, `readBlobFile`/`writeBlobFile` — nothing here
// leaks into sync.js's merge logic, same separation as the native app.
//
// Scope note: this uses the full `drive` scope (not the safer `drive.file`)
// because the app needs to open a folder the user already owns/was shared,
// identified only by its link — `drive.file` would only grant access to files
// the app itself created. That means this OAuth client must stay in Google
// Cloud Console's "Testing" publishing status with explicit test users added
// (see README) rather than going through full verification, which is the
// normal, supported way to run a personal/family app like this indefinitely.

const DRIVE_API = "https://www.googleapis.com/drive/v3";
const DRIVE_UPLOAD_API = "https://www.googleapis.com/upload/drive/v3";
const SCOPE = "https://www.googleapis.com/auth/drive";
const TOKEN_STORAGE_KEY = "carrycard.driveToken";

/** Thrown when a Drive call needs a token we don't have. The caller (sync.js)
 * decides what to do with this — it is never handled by silently trying to
 * pop up a sign-in window, see NotAuthorizedError usage below for why. */
export class NotAuthorizedError extends Error {
  constructor() {
    super("Not signed in to Google Drive.");
    this.name = "NotAuthorizedError";
  }
}

/** Pulls Google's actual error message + reason (e.g. "accessNotConfigured",
 * "insufficientPermissions", "notFound") out of a failed response body, so
 * failures surface as something actionable instead of a bare HTTP status. */
async function driveErrorDetail(res) {
  try {
    const body = await res.json();
    const detail = body?.error?.errors?.[0];
    const reason = detail?.reason || body?.error?.status;
    const message = body?.error?.message || res.statusText;
    return reason ? `${message} (${reason})` : `${message} (HTTP ${res.status})`;
  } catch {
    return `HTTP ${res.status}`;
  }
}

export function extractFolderId(input) {
  const trimmed = input.trim();
  const match = trimmed.match(/\/folders\/([a-zA-Z0-9_-]+)/);
  if (match) return match[1];
  if (/^[a-zA-Z0-9_-]{10,}$/.test(trimmed)) return trimmed; // looks like a bare ID
  return null;
}

export class DriveClient {
  constructor(clientId) {
    this.clientId = clientId;
    this.accessToken = null;
    this._expiresAt = 0;
    this._loadStoredToken();
    this._consumeRedirectToken();
  }

  get isAuthorized() {
    return !!this.accessToken && Date.now() < this._expiresAt;
  }

  /** Sends the whole page to Google's consent screen; Google redirects back to
   * this exact page with the token in the URL fragment (picked up by
   * `_consumeRedirectToken` on the next load). Deliberately a full-page
   * redirect, not a `window.open` popup: popups opened from an installed iOS
   * "Add to Home Screen" app are unreliable — often silently blocked — a
   * well-documented standalone-mode limitation, not something fixable from
   * inside the popup call itself. Only call this from a direct user action
   * (a button's own click handler), since it navigates away immediately. */
  beginAuthorization() {
    const redirectUri = window.location.origin + window.location.pathname;
    const params = new URLSearchParams({
      client_id: this.clientId,
      redirect_uri: redirectUri,
      response_type: "token",
      scope: SCOPE,
      include_granted_scopes: "true",
      prompt: "consent",
    });
    window.location.href = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
  }

  signOut() {
    this.accessToken = null;
    this._expiresAt = 0;
    localStorage.removeItem(TOKEN_STORAGE_KEY);
  }

  _loadStoredToken() {
    try {
      const saved = JSON.parse(localStorage.getItem(TOKEN_STORAGE_KEY));
      if (saved?.accessToken && saved.expiresAt > Date.now()) {
        this.accessToken = saved.accessToken;
        this._expiresAt = saved.expiresAt;
      }
    } catch {
      // ignore malformed/missing storage
    }
  }

  _storeToken() {
    localStorage.setItem(
      TOKEN_STORAGE_KEY,
      JSON.stringify({ accessToken: this.accessToken, expiresAt: this._expiresAt })
    );
  }

  /** Picks up `#access_token=...` left in the URL by Google after
   * `beginAuthorization()` redirects back here, then scrubs it from the
   * visible URL (it's a bearer credential — it shouldn't linger in browser
   * history or get shared if the user copies the URL). */
  _consumeRedirectToken() {
    if (!window.location.hash.includes("access_token=")) return;
    const params = new URLSearchParams(window.location.hash.slice(1));
    const token = params.get("access_token");
    const expiresIn = Number(params.get("expires_in") || 3600);
    if (token) {
      this.accessToken = token;
      this._expiresAt = Date.now() + expiresIn * 1000;
      this._storeToken();
    }
    history.replaceState(null, "", window.location.pathname + window.location.search);
  }

  async _fetch(url, options = {}) {
    if (!this.isAuthorized) throw new NotAuthorizedError();
    const response = await fetch(url, {
      ...options,
      headers: { ...(options.headers || {}), Authorization: `Bearer ${this.accessToken}` },
    });
    if (response.status === 401) {
      // Token expired or was revoked server-side — forget it so `isAuthorized`
      // correctly reflects reality; the caller decides whether to re-prompt.
      this.signOut();
      throw new NotAuthorizedError();
    }
    return response;
  }

  async getFolderName(folderId) {
    const res = await this._fetch(`${DRIVE_API}/files/${folderId}?fields=name&supportsAllDrives=true`);
    if (!res.ok) throw new Error(`Couldn't read folder: ${await driveErrorDetail(res)}`);
    const data = await res.json();
    return data.name;
  }

  async findChild(folderId, name) {
    const q = encodeURIComponent(`'${folderId}' in parents and name = '${name}' and trashed = false`);
    const res = await this._fetch(
      `${DRIVE_API}/files?q=${q}&fields=files(id,name)&supportsAllDrives=true&includeItemsFromAllDrives=true`
    );
    if (!res.ok) throw new Error(`Couldn't list folder contents: ${await driveErrorDetail(res)}`);
    const data = await res.json();
    return data.files?.[0] || null;
  }

  async ensureSubfolder(parentId, name) {
    const existing = await this.findChild(parentId, name);
    if (existing) return existing.id;
    const res = await this._fetch(`${DRIVE_API}/files?supportsAllDrives=true`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, mimeType: "application/vnd.google-apps.folder", parents: [parentId] }),
    });
    if (!res.ok) throw new Error(`Couldn't create "${name}" folder: ${await driveErrorDetail(res)}`);
    const created = await res.json();
    return created.id;
  }

  /** Resolves the actual sync folder: the given folder itself if it's already
   * named "Carry-Card", otherwise a "Carry-Card" subfolder inside it — same
   * rule as SyncService.resolveSyncDirectory in the native app. */
  async resolveSyncFolder(rootFolderId) {
    const name = await this.getFolderName(rootFolderId);
    if (name.toLowerCase() === "carry-card") return rootFolderId;
    return this.ensureSubfolder(rootFolderId, "Carry-Card");
  }

  async readJSONFile(folderId, name) {
    const file = await this.findChild(folderId, name);
    if (!file) return null;
    const res = await this._fetch(`${DRIVE_API}/files/${file.id}?alt=media&supportsAllDrives=true`);
    if (!res.ok) return null;
    try {
      return await res.json();
    } catch {
      return null; // malformed remote JSON — treated as absent, never crashes the sync
    }
  }

  async writeJSONFile(folderId, name, data) {
    await this._writeMultipart(folderId, name, "application/json", JSON.stringify(data, null, 2));
  }

  async readBlobFile(folderId, name) {
    const file = await this.findChild(folderId, name);
    if (!file) return null;
    const res = await this._fetch(`${DRIVE_API}/files/${file.id}?alt=media&supportsAllDrives=true`);
    if (!res.ok) return null;
    return res.blob();
  }

  async writeBlobFile(folderId, name, blob) {
    await this._writeMultipart(folderId, name, blob.type || "application/octet-stream", blob);
  }

  async listFileNames(folderId) {
    const q = encodeURIComponent(`'${folderId}' in parents and trashed = false`);
    const res = await this._fetch(
      `${DRIVE_API}/files?q=${q}&fields=files(name)&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true`
    );
    if (!res.ok) return [];
    const data = await res.json();
    return (data.files || []).map((f) => f.name);
  }

  async _writeMultipart(folderId, name, mimeType, bodyPart) {
    const existing = await this.findChild(folderId, name);
    const metadata = { name, mimeType, ...(existing ? {} : { parents: [folderId] }) };
    const boundary = "carrycard-boundary";
    const head = `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`;
    const tail = `\r\n--${boundary}--`;
    const requestBody = new Blob([head, bodyPart, tail]);

    const url = existing
      ? `${DRIVE_UPLOAD_API}/files/${existing.id}?uploadType=multipart&supportsAllDrives=true`
      : `${DRIVE_UPLOAD_API}/files?uploadType=multipart&supportsAllDrives=true`;
    const res = await this._fetch(url, {
      method: existing ? "PATCH" : "POST",
      headers: { "Content-Type": `multipart/related; boundary=${boundary}` },
      body: requestBody,
    });
    if (!res.ok) throw new Error(`Couldn't write "${name}" to Drive: ${await driveErrorDetail(res)}`);
  }
}
