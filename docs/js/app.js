import { CardStore, ImageStore } from "./db.js";
import { newCard, tombstone, BARCODE_TYPES, BARCODE_DISPLAY_NAMES, DEFAULT_PALETTE, deriveColor, colorToCss } from "./model.js";
import { renderBarcode } from "./barcodeRender.js";
import { BarcodeScanner } from "./barcodeScan.js";
import { SyncService } from "./sync.js";
import { GOOGLE_CLIENT_ID } from "./config.js";

const RECENTLY_USED_KEY = "carrycard.recentlyUsed";

const app = document.getElementById("app");
const sync = new SyncService(GOOGLE_CLIENT_ID);

let cards = [];
let route = { name: "list" };
let logoObjectUrls = new Map(); // fileName -> blob: URL, revoked on next render pass
let pendingLogoBlob = null; // set while the editor has an unsaved picked image
let scanner = null;

sync.onChange(() => {
  if (route.name === "settings") render();
});

async function loadCards() {
  const db = await CardStore.load();
  cards = db.cards.slice().sort((a, b) => a.sortIndex - b.sortIndex);
}

async function syncAndReload() {
  await sync.sync();
  await loadCards();
  render();
}

function initials(name) {
  const letters = name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]);
  return (letters.join("") || "?").toUpperCase();
}

function cardColorCss(card) {
  const color = card.backgroundColor || deriveColor(card.name);
  return `linear-gradient(135deg, ${colorToCss(color, 1)}, ${colorToCss(color, 0.82)})`;
}

function codeSuffix(code) {
  const trimmed = code.trim();
  return trimmed.length > 4 ? trimmed.slice(-4) : trimmed;
}

function loadRecentlyUsed() {
  try {
    return JSON.parse(localStorage.getItem(RECENTLY_USED_KEY)) || {};
  } catch {
    return {};
  }
}

function markUsed(cardId) {
  const map = loadRecentlyUsed();
  map[cardId] = new Date().toISOString();
  localStorage.setItem(RECENTLY_USED_KEY, JSON.stringify(map));
}

function featuredCard() {
  const map = loadRecentlyUsed();
  let best = null;
  let bestTime = 0;
  for (const card of cards) {
    const t = map[card.id];
    if (t && new Date(t).getTime() > bestTime) {
      best = card;
      bestTime = new Date(t).getTime();
    }
  }
  return best;
}

// --- logo image loading (object URLs, revoked between renders to avoid leaks) ---

async function logoImgTag(fileName, className) {
  if (!fileName) return null;
  const blob = await ImageStore.loadLogo(fileName);
  if (!blob) return null;
  const url = URL.createObjectURL(blob);
  logoObjectUrls.set(`${className}-${fileName}-${Math.random()}`, url);
  return url;
}

function revokeLogoUrls() {
  for (const url of logoObjectUrls.values()) URL.revokeObjectURL(url);
  logoObjectUrls.clear();
}

// --- persistence actions (mirrors CardListViewModel.swift) ---

async function saveCard(card) {
  const db = await CardStore.load();
  const now = new Date().toISOString();
  const updated = { ...card, updatedAt: now };
  const index = db.cards.findIndex((c) => c.id === card.id);
  if (index >= 0) {
    db.cards[index] = updated;
  } else {
    if (!updated.sortIndex) {
      const maxIndex = db.cards.reduce((m, c) => Math.max(m, c.sortIndex), 0);
      updated.sortIndex = maxIndex + 1;
    }
    db.cards.push(updated);
  }
  db.deletedCards = db.deletedCards.filter((d) => d.id !== card.id);
  await CardStore.save(db);
  await loadCards();
  render();
  await syncAndReload();
}

async function deleteCard(card) {
  const db = await CardStore.load();
  db.cards = db.cards.filter((c) => c.id !== card.id);
  db.deletedCards = db.deletedCards.filter((d) => d.id !== card.id);
  db.deletedCards.push(tombstone(card.id));
  await CardStore.save(db);

  if (card.logoFileName) {
    const stillReferenced = db.cards.some((c) => c.logoFileName === card.logoFileName);
    if (!stillReferenced) await ImageStore.deleteLogo(card.logoFileName);
  }

  await loadCards();
  route = { name: "list" };
  render();
  await syncAndReload();
}

async function moveCard(fromIndex, toIndex) {
  const reordered = cards.slice();
  const [moved] = reordered.splice(fromIndex, 1);
  reordered.splice(toIndex, 0, moved);
  reordered.forEach((c, i) => {
    c.sortIndex = i;
    c.updatedAt = new Date().toISOString();
  });
  cards = reordered;
  render();

  const db = await CardStore.load();
  for (const card of reordered) {
    const idx = db.cards.findIndex((c) => c.id === card.id);
    if (idx >= 0) db.cards[idx] = card;
  }
  await CardStore.save(db);
  await syncAndReload();
}

// --- rendering ---

function el(html) {
  const template = document.createElement("template");
  template.innerHTML = html.trim();
  return template.content.firstElementChild;
}

async function render() {
  revokeLogoUrls();
  app.innerHTML = "";
  if (route.name === "list") app.appendChild(await renderList());
  else if (route.name === "detail") app.appendChild(await renderDetail(route.cardId));
  else if (route.name === "editor") app.appendChild(await renderEditor(route.cardId));
  else if (route.name === "settings") app.appendChild(await renderSettings());
}

async function renderList() {
  if (cards.length === 0) {
    const screen = el(`
      <div class="screen">
        <header class="top-bar">
          <button class="icon-button" id="settings-btn">⚙️</button>
          <button class="icon-button" id="add-btn">➕</button>
        </header>
        <h1 class="page-title">Carry-Card</h1>
        <main>
          <div class="empty-state">
            <div class="glyph">🪪</div>
            <h2>No cards yet</h2>
            <p>Add your loyalty cards to keep them all in one place.</p>
            <button class="primary-button" id="add-first-btn">＋ Add Your First Card</button>
          </div>
        </main>
      </div>
    `);
    screen.querySelector("#settings-btn").onclick = () => { route = { name: "settings" }; render(); };
    screen.querySelector("#add-btn").onclick = () => { route = { name: "editor", cardId: null }; render(); };
    screen.querySelector("#add-first-btn").onclick = () => { route = { name: "editor", cardId: null }; render(); };
    return screen;
  }

  const featured = featuredCard();
  const screen = el(`
    <div class="screen">
      <header class="top-bar">
        <button class="icon-button" id="settings-btn">⚙️</button>
        <button class="icon-button" id="add-btn">➕</button>
      </header>
      <h1 class="page-title">Carry-Card</h1>
      <main>
        <div id="featured-slot"></div>
        <div class="card-grid" id="grid"></div>
      </main>
    </div>
  `);
  screen.querySelector("#settings-btn").onclick = () => { route = { name: "settings" }; render(); };
  screen.querySelector("#add-btn").onclick = () => { route = { name: "editor", cardId: null }; render(); };

  if (featured) {
    const logoUrl = await logoImgTag(featured.logoFileName, "featured");
    const node = el(`
      <button class="featured-card" style="background:${cardColorCss(featured)}">
        <div class="logo-bubble">${logoUrl ? `<img src="${logoUrl}">` : initials(featured.name)}</div>
        <div>
          <div class="eyebrow">Recently Used</div>
          <div class="name">${escapeHtml(featured.name)}</div>
          <div class="code-suffix">···· ${escapeHtml(codeSuffix(featured.code))}</div>
        </div>
        <div class="chevron">›</div>
      </button>
    `);
    node.onclick = () => openDetail(featured.id);
    screen.querySelector("#featured-slot").appendChild(node);
  }

  const grid = screen.querySelector("#grid");
  for (const card of cards) {
    const logoUrl = await logoImgTag(card.logoFileName, "grid");
    const node = el(`
      <button class="grid-card" style="background:${cardColorCss(card)}" draggable="true">
        <div class="logo-bubble">${logoUrl ? `<img src="${logoUrl}">` : initials(card.name)}</div>
        <div class="spacer"></div>
        <div class="name">${escapeHtml(card.name)}</div>
        <div class="code-suffix">···· ${escapeHtml(codeSuffix(card.code))}</div>
      </button>
    `);
    node.onclick = () => openDetail(card.id);
    node.addEventListener("contextmenu", (event) => {
      event.preventDefault();
      if (confirm(`Delete "${card.name}"? It will be removed from all your synced devices.`)) {
        deleteCard(card);
      }
    });
    let pressTimer;
    node.addEventListener("touchstart", () => {
      pressTimer = setTimeout(() => {
        if (confirm(`Delete "${card.name}"? It will be removed from all your synced devices.`)) {
          deleteCard(card);
        }
      }, 650);
    });
    node.addEventListener("touchend", () => clearTimeout(pressTimer));
    node.addEventListener("touchmove", () => clearTimeout(pressTimer));

    node.addEventListener("dragstart", (event) => {
      event.dataTransfer.setData("text/plain", card.id);
    });
    node.addEventListener("dragover", (event) => event.preventDefault());
    node.addEventListener("drop", (event) => {
      event.preventDefault();
      const draggedId = event.dataTransfer.getData("text/plain");
      const fromIndex = cards.findIndex((c) => c.id === draggedId);
      const toIndex = cards.findIndex((c) => c.id === card.id);
      if (fromIndex >= 0 && toIndex >= 0 && fromIndex !== toIndex) moveCard(fromIndex, toIndex);
    });

    grid.appendChild(node);
  }

  return screen;
}

function openDetail(cardId) {
  markUsed(cardId);
  route = { name: "detail", cardId };
  render();
}

async function renderDetail(cardId) {
  const card = cards.find((c) => c.id === cardId);
  if (!card) {
    route = { name: "list" };
    return renderList();
  }

  const logoUrl = await logoImgTag(card.logoFileName, "detail");
  const screen = el(`
    <div class="screen">
      <div class="detail-header">
        <button class="back-button" id="back-btn">‹</button>
        <div class="detail-title">${escapeHtml(card.name)}</div>
        <button class="secondary-button" id="edit-btn" style="margin-right:8px;">Edit</button>
      </div>
      <div class="detail-body">
        <div class="logo-bubble detail-logo" style="background:${cardColorCss(card)}">
          ${logoUrl ? `<img src="${logoUrl}">` : `<span style="font-size:26px">${initials(card.name)}</span>`}
        </div>
        <div class="detail-name">${escapeHtml(card.name)}</div>
        <div class="barcode-card"><canvas id="barcode-canvas" aria-label="Loyalty card barcode, number ${escapeHtml(card.code)}"></canvas></div>
        <div class="code-text">${escapeHtml(card.code)}</div>
        <div class="detail-actions">
          <button class="danger-button" id="delete-btn">🗑 Delete Card</button>
        </div>
      </div>
    </div>
  `);

  screen.querySelector("#back-btn").onclick = () => { route = { name: "list" }; render(); };
  screen.querySelector("#edit-btn").onclick = () => { route = { name: "editor", cardId: card.id }; render(); };
  screen.querySelector("#delete-btn").onclick = () => {
    if (confirm(`Delete "${card.name}"? It will be removed from all your synced devices.`)) deleteCard(card);
  };

  const canvas = screen.querySelector("#barcode-canvas");
  requestAnimationFrame(() => {
    const ok = renderBarcode(canvas, card.code, card.barcodeType, 320, 140);
    if (!ok) {
      canvas.replaceWith(el(`<p class="helper-text">This barcode type couldn't be rendered.</p>`));
    }
  });

  return screen;
}

async function renderEditor(cardId) {
  const existing = cardId ? cards.find((c) => c.id === cardId) : null;
  pendingLogoBlob = null;
  let draft = existing
    ? { ...existing }
    : { id: null, name: "", code: "", barcodeType: "code128", logoFileName: null, backgroundColor: null };
  let colorManuallySet = !!draft.backgroundColor;

  const screen = el(`
    <div class="sheet">
      <div class="sheet-header">
        <button id="cancel-btn">Cancel</button>
        <div class="title">${existing ? "Edit Card" : "New Card"}</div>
        <button id="save-btn" style="color:var(--accent);font-weight:700;">Save</button>
      </div>

      <div class="form-section" style="text-align:center;">
        <button class="logo-picker-preview" id="logo-preview" style="background:${cardColorCss(draft.backgroundColor ? draft : { name: draft.name || "?" })}">
          ${draft.name ? initials(draft.name) : "?"}
        </button>
        <input type="file" accept="image/*" id="logo-file-input" style="display:none;">
        <p class="helper-text" style="text-align:center;">Tap to choose a logo photo</p>
      </div>

      <div class="form-section">
        <div class="label">Merchant</div>
        <div class="form-card">
          <div class="form-row"><input type="text" id="name-input" placeholder="Merchant name" value="${escapeHtmlAttr(draft.name)}"></div>
        </div>
      </div>

      <div class="form-section">
        <div class="label">Loyalty Code</div>
        <div class="form-card">
          <div class="form-row"><input type="text" id="code-input" placeholder="Code" value="${escapeHtmlAttr(draft.code)}"></div>
          <div class="form-row">
            <span>Barcode Type</span>
            <select id="type-select" style="margin-left:auto;">
              ${BARCODE_TYPES.map((t) => `<option value="${t}" ${t === draft.barcodeType ? "selected" : ""}>${BARCODE_DISPLAY_NAMES[t]}</option>`).join("")}
            </select>
          </div>
          <button class="form-row button-row" id="scan-btn">📷 Scan Barcode</button>
        </div>
      </div>

      <div class="form-section">
        <div class="label">Color</div>
        <div class="swatch-row" id="swatch-row"></div>
      </div>

      ${existing ? `<div class="form-section"><button class="form-card danger-button" style="width:100%;padding:13px;" id="delete-btn">Delete Card</button></div>` : ""}
    </div>
  `);

  screen.querySelector("#cancel-btn").onclick = () => {
    route = existing ? { name: "detail", cardId: existing.id } : { name: "list" };
    render();
  };

  const nameInput = screen.querySelector("#name-input");
  const codeInput = screen.querySelector("#code-input");
  const typeSelect = screen.querySelector("#type-select");
  const logoPreview = screen.querySelector("#logo-preview");
  const logoFileInput = screen.querySelector("#logo-file-input");

  nameInput.oninput = () => {
    draft.name = nameInput.value;
    if (!pendingLogoBlob && !draft.logoFileName) logoPreview.textContent = draft.name ? initials(draft.name) : "?";
    if (!colorManuallySet) logoPreview.style.background = cardColorCss({ name: draft.name || "?" });
  };

  logoPreview.onclick = () => logoFileInput.click();
  logoFileInput.onchange = async () => {
    const file = logoFileInput.files[0];
    if (!file) return;
    pendingLogoBlob = file;
    const url = URL.createObjectURL(file);
    logoPreview.innerHTML = `<img src="${url}">`;
  };

  const swatchRow = screen.querySelector("#swatch-row");
  DEFAULT_PALETTE.forEach((color) => {
    const swatch = el(`<button class="swatch" style="background:${colorToCss(color)}"></button>`);
    swatch.onclick = () => {
      draft.backgroundColor = color;
      colorManuallySet = true;
      if (!pendingLogoBlob && !draft.logoFileName) logoPreview.style.background = cardColorCss(draft);
    };
    swatchRow.appendChild(swatch);
  });

  screen.querySelector("#scan-btn").onclick = () => openScanner((result) => {
    codeInput.value = result.value;
    typeSelect.value = result.barcodeType;
    draft.code = result.value;
    draft.barcodeType = result.barcodeType;
  });

  if (existing) {
    screen.querySelector("#delete-btn").onclick = () => {
      if (confirm(`Delete "${existing.name}"? It will be removed from all your synced devices.`)) deleteCard(existing);
    };
  }

  screen.querySelector("#save-btn").onclick = async () => {
    const name = nameInput.value.trim();
    const code = codeInput.value.trim();
    if (!name || !code) {
      alert("Enter a merchant name and a code.");
      return;
    }

    let logoFileName = draft.logoFileName;
    if (pendingLogoBlob) {
      const fileName = `${crypto.randomUUID()}.jpg`;
      const resized = await resizeImageToJpeg(pendingLogoBlob, 512, 0.85);
      await ImageStore.saveLogo(fileName, resized);
      if (draft.logoFileName) await ImageStore.deleteLogo(draft.logoFileName);
      logoFileName = fileName;
    }

    const finalColor = colorManuallySet ? draft.backgroundColor : deriveColor(name);

    const card = existing
      ? { ...existing, name, code, barcodeType: typeSelect.value, logoFileName, backgroundColor: finalColor }
      : newCard({ name, code, barcodeType: typeSelect.value, logoFileName, backgroundColor: finalColor });

    route = { name: "detail", cardId: card.id };
    await saveCard(card);
  };

  return screen;
}

async function renderSettings() {
  const s = sync.state;
  const screen = el(`
    <div class="sheet">
      <div class="sheet-header">
        <span></span>
        <div class="title">Settings</div>
        <button id="done-btn" style="color:var(--accent);font-weight:700;">Done</button>
      </div>

      <div class="form-section">
        <p class="helper-text">Carry-Card stores every loyalty card on this device and works fully offline.</p>
      </div>

      <div class="form-section">
        <div class="label">Synchronization</div>
        <div class="form-card">
          <div class="status-row"><span>Status</span><span class="${s.status === "success" ? "status-ok" : s.status === "failure" ? "status-warn" : "status-value"}">${statusLabel(s)}</span></div>
          ${s.isEnabled ? `<div class="status-row"><span>Folder</span><span class="status-value">${escapeHtml(s.folderLink || "")}</span></div>` : ""}
          ${s.lastSuccessfulSyncAt ? `<div class="status-row"><span>Last Synced</span><span class="status-value">${new Date(s.lastSuccessfulSyncAt).toLocaleString()}</span></div>` : ""}
          ${s.lastErrorMessage ? `<div class="status-row"><span>⚠️</span><span class="status-value">${escapeHtml(s.lastErrorMessage)}</span></div>` : ""}
          ${s.isEnabled ? `
            <button class="form-row button-row" id="sync-now-btn">🔄 Sync Now</button>
            <button class="form-row button-row" id="change-folder-btn">Change Sync Folder</button>
            <button class="form-row button-row danger-button" id="disconnect-btn">Disconnect Sync Folder</button>
          ` : `
            <div class="form-row" style="flex-direction:column;align-items:stretch;gap:8px;">
              <p class="helper-text" style="padding:0;">Paste a Google Drive folder link (Share → Copy link) to keep your cards in sync across devices.</p>
              <input type="text" id="folder-link-input" placeholder="https://drive.google.com/drive/folders/...">
            </div>
            <button class="form-row button-row" id="connect-btn">Connect Sync Folder</button>
          `}
        </div>
      </div>

      <div class="form-section">
        <div class="label">About</div>
        <div class="form-card">
          <div class="status-row"><span>Version</span><span class="status-value">1.0 (web)</span></div>
        </div>
        <p class="helper-text">Carry-Card collects no analytics and has no servers of its own. Your cards never leave this device unless you connect a sync folder — sync then talks directly to Google Drive, using your own Google sign-in.</p>
      </div>
    </div>
  `);

  screen.querySelector("#done-btn").onclick = () => { route = { name: "list" }; render(); };

  if (s.isEnabled) {
    screen.querySelector("#sync-now-btn").onclick = async () => { await syncAndReload(); };
    screen.querySelector("#change-folder-btn").onclick = () => {
      const link = prompt("Paste the new Google Drive folder link:", s.folderLink || "");
      if (link) sync.setFolderLink(link).then(() => { loadCards().then(render); });
    };
    screen.querySelector("#disconnect-btn").onclick = () => {
      if (confirm("Disconnect the sync folder? Your cards stay on this device.")) {
        sync.disconnect();
        render();
      }
    };
  } else {
    screen.querySelector("#connect-btn").onclick = async () => {
      const link = screen.querySelector("#folder-link-input").value.trim();
      if (!link) return;
      await sync.setFolderLink(link);
      await loadCards();
      render();
    };
  }

  return screen;
}

function statusLabel(s) {
  if (s.status === "syncing") return "Syncing…";
  if (s.status === "success") return "Up to date";
  if (s.status === "failure") return "Sync issue";
  return s.isEnabled ? "Not yet synced" : "Off";
}

// --- scanner overlay ---

async function openScanner(onConfirm) {
  const overlay = el(`
    <div class="scanner-overlay">
      <div class="scanner-top-bar">
        <button id="scanner-cancel">Cancel</button>
        <button id="scanner-manual">Enter Manually</button>
      </div>
      <div class="scanner-video-wrap">
        <video id="scanner-video" autoplay playsinline muted></video>
        <div class="scanner-hint">Point the camera at a loyalty card barcode</div>
      </div>
    </div>
  `);
  document.body.appendChild(overlay);

  const close = () => {
    scanner?.stop();
    overlay.remove();
  };
  overlay.querySelector("#scanner-cancel").onclick = close;
  overlay.querySelector("#scanner-manual").onclick = close;

  const video = overlay.querySelector("#scanner-video");
  scanner = new BarcodeScanner();
  try {
    await scanner.start(video, (result) => {
      showConfirmCard(overlay, result, (finalValue) => {
        close();
        onConfirm({ value: finalValue, barcodeType: result.barcodeType });
      });
    });
  } catch (error) {
    overlay.querySelector(".scanner-video-wrap").innerHTML = `
      <div style="color:#fff;text-align:center;padding:40px 24px;">
        <p style="font-weight:700;margin-bottom:8px;">Camera Access Needed</p>
        <p style="opacity:0.8;font-size:14px;">Carry-Card uses the camera only to scan loyalty-card barcodes. Allow camera access, or enter the code manually.</p>
      </div>`;
    console.warn("Camera error", error);
  }
}

function showConfirmCard(overlay, result, onUse) {
  const existing = overlay.querySelector(".scan-confirm");
  if (existing) existing.remove();
  const card = el(`
    <div class="scan-confirm">
      <div class="type-label">${BARCODE_DISPLAY_NAMES[result.barcodeType] || result.barcodeType}</div>
      <input type="text" id="confirm-value" value="${escapeHtmlAttr(result.value)}">
      <div class="buttons">
        <button class="again-btn" id="scan-again">Scan Again</button>
        <button class="use-btn" id="use-code">Use This Code</button>
      </div>
    </div>
  `);
  overlay.querySelector(".scanner-video-wrap").appendChild(card);
  card.querySelector("#scan-again").onclick = () => {
    card.remove();
    scanner.start(overlay.querySelector("#scanner-video"), (r) => showConfirmCard(overlay, r, onUse));
  };
  card.querySelector("#use-code").onclick = () => {
    const value = card.querySelector("#confirm-value").value.trim();
    if (value) onUse(value);
  };
}

// --- helpers ---

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function escapeHtmlAttr(str) {
  return escapeHtml(str);
}

function resizeImageToJpeg(fileOrBlob, maxDimension, quality) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      let { width, height } = img;
      if (Math.max(width, height) > maxDimension) {
        const scale = maxDimension / Math.max(width, height);
        width = Math.round(width * scale);
        height = Math.round(height * scale);
      }
      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "#fff";
      ctx.fillRect(0, 0, width, height);
      ctx.drawImage(img, 0, 0, width, height);
      canvas.toBlob((blob) => resolve(blob), "image/jpeg", quality);
      URL.revokeObjectURL(img.src);
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(fileOrBlob);
  });
}

// --- boot ---

async function boot() {
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
  await loadCards();
  render();
  if (sync.state.isEnabled) syncAndReload();
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") syncAndReload();
  });
}

boot();
