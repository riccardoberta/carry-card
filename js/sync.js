// Sync orchestration — the web equivalent of SyncService.swift. Same shape:
// load local, resolve/read remote, merge, copy logos both ways, write remote,
// write local. A failure never touches local data; success is all-or-nothing.
import { CardStore, ImageStore } from "./db.js";
import { mergeDatabases } from "./model.js";
import { DriveClient, extractFolderId } from "./driveSync.js";

const SETTINGS_KEY = "carrycard.settings";

function loadSettings() {
  try {
    return JSON.parse(localStorage.getItem(SETTINGS_KEY)) || {};
  } catch {
    return {};
  }
}

function saveSettings(settings) {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
}

export class SyncService {
  constructor(clientId) {
    this.client = new DriveClient(clientId);
    this.state = {
      isEnabled: false,
      folderLink: null,
      lastSuccessfulSyncAt: null,
      status: "neverSynced", // neverSynced | syncing | success | failure
      lastErrorMessage: null,
    };
    this._isSyncing = false;
    this._listeners = new Set();
    this._loadPersistedState();
  }

  onChange(fn) {
    this._listeners.add(fn);
    return () => this._listeners.delete(fn);
  }

  _notify() {
    for (const fn of this._listeners) fn(this.state);
  }

  _loadPersistedState() {
    const settings = loadSettings();
    if (settings.folderLink) {
      this.state.isEnabled = true;
      this.state.folderLink = settings.folderLink;
    }
    if (settings.lastSuccessfulSyncAt) this.state.lastSuccessfulSyncAt = settings.lastSuccessfulSyncAt;
  }

  _persist() {
    saveSettings({ folderLink: this.state.folderLink, lastSuccessfulSyncAt: this.state.lastSuccessfulSyncAt });
  }

  /** Adopts a folder link (as pasted from Drive's "Share" menu) and syncs immediately. */
  async setFolderLink(link) {
    const id = extractFolderId(link);
    if (!id) {
      this.state.lastErrorMessage = "That doesn't look like a Google Drive folder link.";
      this._notify();
      return false;
    }
    this.state.folderLink = link;
    this.state.isEnabled = true;
    this.state.lastErrorMessage = null;
    this._persist();
    this._notify();
    await this.sync();
    return true;
  }

  disconnect() {
    this.client.signOut();
    this.state = {
      isEnabled: false,
      folderLink: null,
      lastSuccessfulSyncAt: null,
      status: "neverSynced",
      lastErrorMessage: null,
    };
    this._persist();
    this._notify();
  }

  async sync() {
    if (!this.state.isEnabled || this._isSyncing) return;
    this._isSyncing = true;
    this.state.status = "syncing";
    this._notify();

    try {
      const rootId = extractFolderId(this.state.folderLink);
      const folderId = await this.client.resolveSyncFolder(rootId);

      const local = await CardStore.load();
      const remoteCards = (await this.client.readJSONFile(folderId, "cards.json")) || [];
      const remoteDeleted = (await this.client.readJSONFile(folderId, "deleted.json")) || [];
      const merged = mergeDatabases(local, { cards: remoteCards, deletedCards: remoteDeleted });

      await this._syncLogos(folderId, merged.cards);
      await this.client.writeJSONFile(folderId, "cards.json", merged.cards);
      await this.client.writeJSONFile(folderId, "deleted.json", merged.deletedCards);
      await CardStore.save(merged);

      this.state.status = "success";
      this.state.lastSuccessfulSyncAt = new Date().toISOString();
      this.state.lastErrorMessage = null;
    } catch (error) {
      console.error("Sync failed", error);
      this.state.status = "failure";
      this.state.lastErrorMessage = error?.message || String(error);
    } finally {
      this._isSyncing = false;
      this._persist();
      this._notify();
    }
  }

  async _syncLogos(folderId, cards) {
    const remoteNames = new Set(await this.client.listFileNames(folderId));
    const localNames = new Set(await ImageStore.allFileNames());
    for (const card of cards) {
      if (!card.logoFileName) continue;
      const name = card.logoFileName;
      if (localNames.has(name) && !remoteNames.has(name)) {
        const blob = await ImageStore.loadLogo(name);
        if (blob) await this.client.writeBlobFile(folderId, name, blob);
      } else if (remoteNames.has(name) && !localNames.has(name)) {
        const blob = await this.client.readBlobFile(folderId, name);
        if (blob) await ImageStore.saveLogo(name, blob);
      }
    }
  }
}
