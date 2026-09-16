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
    this.tokenClient = null;
  }

  get isAuthorized() {
    return !!this.accessToken;
  }

  /** Requests an access token. `interactive: true` shows the Google consent
   * popup (call this from a user gesture, e.g. a button tap); with `false` it
   * only succeeds if a token can be issued silently. */
  authorize({ interactive } = { interactive: true }) {
    return new Promise((resolve, reject) => {
      this.tokenClient = window.google.accounts.oauth2.initTokenClient({
        client_id: this.clientId,
        scope: SCOPE,
        callback: (response) => {
          if (response.error) {
            reject(new Error(response.error));
            return;
          }
          this.accessToken = response.access_token;
          resolve(this.accessToken);
        },
      });
      this.tokenClient.requestAccessToken({ prompt: interactive ? "consent" : "" });
    });
  }

  signOut() {
    if (this.accessToken) {
      window.google?.accounts?.oauth2?.revoke(this.accessToken, () => {});
    }
    this.accessToken = null;
  }

  async _fetch(url, options = {}) {
    if (!this.accessToken) await this.authorize({ interactive: true });
    const withAuth = (token) => ({
      ...options,
      headers: { ...(options.headers || {}), Authorization: `Bearer ${token}` },
    });
    let response = await fetch(url, withAuth(this.accessToken));
    if (response.status === 401) {
      this.accessToken = null;
      const fresh = await this.authorize({ interactive: false }).catch(() =>
        this.authorize({ interactive: true })
      );
      response = await fetch(url, withAuth(fresh));
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
