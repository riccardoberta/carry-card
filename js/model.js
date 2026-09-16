// Data model + merge algorithm — a direct port of CarryCard/Models/CardDatabase.swift.
// Keeping this identical to the Swift version means the two apps (native + PWA) stay
// interoperable if they ever sync into the same Drive folder.

export const BARCODE_TYPES = [
  "ean8", "ean13", "upce", "code39", "code93", "code128", "qr", "pdf417", "aztec",
];

export const BARCODE_DISPLAY_NAMES = {
  ean8: "EAN-8",
  ean13: "EAN-13",
  upce: "UPC-E",
  code39: "Code 39",
  code93: "Code 93",
  code128: "Code 128",
  qr: "QR Code",
  pdf417: "PDF417",
  aztec: "Aztec",
};

// Same values as CodableColor.defaultPalette in the native app, so a card's
// derived color looks the same on both platforms.
export const DEFAULT_PALETTE = [
  { red: 0.16, green: 0.35, blue: 0.74 }, // blue
  { red: 0.14, green: 0.58, blue: 0.44 }, // green
  { red: 0.75, green: 0.22, blue: 0.24 }, // red
  { red: 0.55, green: 0.28, blue: 0.68 }, // purple
  { red: 0.86, green: 0.53, blue: 0.09 }, // orange
  { red: 0.20, green: 0.20, blue: 0.24 }, // charcoal
  { red: 0.09, green: 0.55, blue: 0.60 }, // teal
  { red: 0.72, green: 0.30, blue: 0.49 }, // magenta
];

/** Same deterministic idea as CodableColor.derived(from:) in Swift — a
 * simple base-31 rolling hash over the name's code points. Not required to
 * produce bit-identical results to the Swift version (32-bit JS int wrap vs
 * 64-bit Swift Int wrap differ), just a consistent, pleasant default when no
 * explicit color was chosen. */
export function deriveColor(name) {
  let hash = 0;
  for (const ch of name) hash = (hash * 31 + ch.codePointAt(0)) | 0;
  const index = Math.abs(hash) % DEFAULT_PALETTE.length;
  return DEFAULT_PALETTE[index];
}

export function colorToCss(color, opacity = 1) {
  const r = Math.round(color.red * 255);
  const g = Math.round(color.green * 255);
  const b = Math.round(color.blue * 255);
  return `rgb(${r} ${g} ${b} / ${opacity})`;
}

export function newCard({
  name,
  code,
  barcodeType,
  logoFileName = null,
  backgroundColor = null,
  sortIndex = 0,
}) {
  const now = new Date().toISOString();
  return {
    id: crypto.randomUUID().toUpperCase(),
    name,
    code,
    barcodeType,
    logoFileName,
    backgroundColor,
    sortIndex,
    createdAt: now,
    updatedAt: now,
  };
}

export function tombstone(id) {
  return { id, deletedAt: new Date().toISOString() };
}

/**
 * Deterministic, order-independent merge of two databases — same rules as
 * CardDatabase.merged(with:) in Swift:
 *   - same card on both sides: newer `updatedAt` wins
 *   - a tombstone beats any card version whose `updatedAt` is not newer than
 *     the tombstone's `deletedAt`
 *   - an edit made after a deletion (newer updatedAt than deletedAt) restores it
 *   - tombstones merge by keeping the most recent `deletedAt` per id
 */
export function mergeDatabases(a, b) {
  const cardsByID = new Map();
  for (const card of [...a.cards, ...b.cards]) {
    const existing = cardsByID.get(card.id);
    if (!existing || new Date(card.updatedAt) > new Date(existing.updatedAt)) {
      cardsByID.set(card.id, card);
    }
  }

  const tombstonesByID = new Map();
  for (const t of [...a.deletedCards, ...b.deletedCards]) {
    const existing = tombstonesByID.get(t.id);
    if (!existing || new Date(t.deletedAt) > new Date(existing.deletedAt)) {
      tombstonesByID.set(t.id, t);
    }
  }

  const resultCards = [];
  for (const [id, card] of cardsByID) {
    const t = tombstonesByID.get(id);
    if (!t || new Date(card.updatedAt) > new Date(t.deletedAt)) {
      resultCards.push(card);
    }
  }

  resultCards.sort((x, y) => {
    if (x.sortIndex !== y.sortIndex) return x.sortIndex - y.sortIndex;
    return new Date(x.createdAt) - new Date(y.createdAt);
  });

  return { cards: resultCards, deletedCards: [...tombstonesByID.values()] };
}
