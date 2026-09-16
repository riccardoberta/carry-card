// Local-first persistence — the web equivalent of CardStore.swift + ImageStore.swift.
// One IndexedDB database with two object stores: `cards` (metadata, keyed by id) and
// `logos` (image blobs, keyed by file name). Tombstones live in a third store.

const DB_NAME = "carry-card";
const DB_VERSION = 1;

function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("cards")) {
        db.createObjectStore("cards", { keyPath: "id" });
      }
      if (!db.objectStoreNames.contains("deleted")) {
        db.createObjectStore("deleted", { keyPath: "id" });
      }
      if (!db.objectStoreNames.contains("logos")) {
        db.createObjectStore("logos");
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function tx(db, storeNames, mode) {
  return db.transaction(storeNames, mode);
}

function reqToPromise(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export const CardStore = {
  /** Loads the full local database: { cards: [...], deletedCards: [...] } */
  async load() {
    const db = await openDB();
    const t = tx(db, ["cards", "deleted"], "readonly");
    const cards = await reqToPromise(t.objectStore("cards").getAll());
    const deletedCards = await reqToPromise(t.objectStore("deleted").getAll());
    return { cards, deletedCards };
  },

  /** Replaces the entire local database atomically (one IndexedDB transaction). */
  async save(database) {
    const db = await openDB();
    const t = tx(db, ["cards", "deleted"], "readwrite");
    const cardsStore = t.objectStore("cards");
    const deletedStore = t.objectStore("deleted");
    await reqToPromise(cardsStore.clear());
    await reqToPromise(deletedStore.clear());
    for (const card of database.cards) cardsStore.put(card);
    for (const d of database.deletedCards) deletedStore.put(d);
    return new Promise((resolve, reject) => {
      t.oncomplete = () => resolve();
      t.onerror = () => reject(t.error);
    });
  },
};

export const ImageStore = {
  async saveLogo(fileName, blob) {
    const db = await openDB();
    const t = tx(db, ["logos"], "readwrite");
    t.objectStore("logos").put(blob, fileName);
    return new Promise((resolve, reject) => {
      t.oncomplete = () => resolve(fileName);
      t.onerror = () => reject(t.error);
    });
  },

  async loadLogo(fileName) {
    if (!fileName) return null;
    const db = await openDB();
    const t = tx(db, ["logos"], "readonly");
    return reqToPromise(t.objectStore("logos").get(fileName));
  },

  async deleteLogo(fileName) {
    const db = await openDB();
    const t = tx(db, ["logos"], "readwrite");
    t.objectStore("logos").delete(fileName);
    return new Promise((resolve, reject) => {
      t.oncomplete = () => resolve();
      t.onerror = () => reject(t.error);
    });
  },

  async allFileNames() {
    const db = await openDB();
    const t = tx(db, ["logos"], "readonly");
    return reqToPromise(t.objectStore("logos").getAllKeys());
  },
};
