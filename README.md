# Carry-Card

A deliberately simple loyalty-card wallet, installable on your phone straight from the
browser — no App Store, no developer account.

> Open the app → see your loyalty cards → tap one → show a barcode ready to scan.

No payments, no accounts, no login, no server of its own. Carry-Card stores every card
locally on your device and, optionally, syncs it directly with a Google Drive folder
using your own Google sign-in.

**Live app: https://riccardoberta.github.io/carry-card/**

## Features

- **Instant wallet view.** The card list is the first thing you see. Tap a card to get a
  large, high-contrast barcode ready to scan at checkout. The card you opened most
  recently is pinned, enlarged, above the rest.
- **Scan to add.** Point the camera at a barcode and the value/type are captured and
  stay fully editable before saving.
- **Local-first.** Every card lives in the browser's IndexedDB. The app works fully
  offline — including rendering barcodes, which is the one thing it must always be able
  to do — and installs to the Home Screen like a native app (Add to Home Screen).
- **Optional sync, no server.** Paste a Google Drive folder link in Settings; sync talks
  directly to Google's own Drive API using your Google sign-in. Carry-Card itself never
  has a backend to talk to.
- **Deterministic merge.** Two devices editing the same card resolve by last-write-wins;
  deletions propagate via tombstones; a missing or unreachable remote folder never
  erases local data.
- **Privacy by construction.** No analytics, no tracking. Camera access is requested
  only when you tap "Scan Barcode".

## Try it

Visit **https://riccardoberta.github.io/carry-card/** in Safari (or any modern mobile
browser) → Share → **Add to Home Screen**. That's the whole install process.

## Running it locally

No build step — it's plain HTML/CSS/JS.

```bash
python3 -m http.server 8765
```

Then open `http://localhost:8765`. Everything works offline-first without any setup;
Google sign-in only works from an origin that's been authorized on the OAuth client
(see below), so it won't complete from `localhost` unless you add that origin too.

## Architecture

```text
Carry-Card
    ↓
Google Drive REST API (OAuth, your own Google sign-in)
```

There's no Carry-Card server anywhere in this picture — sync is a direct connection
from your browser to Google's own API, authenticated as you.

```text
index.html
manifest.webmanifest   PWA metadata (name, icons, colors)
sw.js                  offline cache — includes the barcode libraries, not just the UI shell
css/app.css
js/
  model.js              LoyaltyCard shape + the deterministic merge algorithm
  db.js                 IndexedDB wrapper (cards + logo image blobs)
  barcodeRender.js       draws a barcode onto a canvas (bwip-js)
  barcodeScan.js         decodes a barcode from the camera (ZXing)
  driveSync.js           Google Drive REST v3 client
  sync.js                sync orchestration: load, merge, write, both sides
  config.js              Google OAuth Client ID
  app.js                 views, routing, all UI wiring
vendor/                 self-hosted copies of bwip-js and ZXing (see "Why vendored" below)
icons/
```

### How sync works

Every sync does the same, deterministic thing:

1. Load the local database (IndexedDB).
2. Read `cards.json` / `deleted.json` from the Drive folder (missing or unreadable
   remote files are treated as empty, never as "erase everything").
3. Merge: same card on both sides → newer `updatedAt` wins. A deletion tombstone beats
   any card version whose `updatedAt` isn't newer than the tombstone's `deletedAt`. An
   edit made *after* a deletion (newer `updatedAt`) restores the card.
4. Copy any logo image missing on either side.
5. Write the merged result back to Drive, then to IndexedDB.

A sync either fully succeeds (both sides end up holding the merged state) or fully
fails and leaves local data untouched — never a partial write.

### Why vendored, not CDN

`vendor/bwip-js-min.js` and `vendor/zxing-min.js` are committed copies, not
`<script src="https://cdn...">` tags. The service worker deliberately never caches
cross-origin requests (that's what keeps Google/Drive calls live), so a CDN-loaded
library could silently fail to load while offline — and rendering a barcode offline is
the one thing this app can never be allowed to get wrong.

## One-time setup for sync (you, not a user of the app)

Carry-Card needs its own Google OAuth Web Client ID to let you sign into Drive:

1. [Google Cloud Console](https://console.cloud.google.com/) → create a project.
2. **APIs & Services → OAuth consent screen** → User type *External* → fill the
   required fields → **stay in "Testing" publishing status** (don't submit for
   verification — for a personal/family app this is the normal, supported way to run it
   indefinitely) → under **Test users**, add every Google account that should be able to
   sign in.
3. **APIs & Services → Library** → search **Google Drive API** → **Enable**. (Creating
   an OAuth client does *not* enable the API by itself — a very common gotcha, and the
   #1 cause of a mysterious 403 on the very first sync.)
4. **APIs & Services → Credentials → Create Credentials → OAuth Client ID** → Application
   type **Web application**:
   - **Authorized JavaScript origins**: the origin the app is served from, e.g.
     `https://riccardoberta.github.io` — no path, no trailing slash.
   - **Authorized redirect URIs**: the *full* app URL, e.g.
     `https://riccardoberta.github.io/carry-card/` — trailing slash matters here. Sign-in
     uses a full-page redirect rather than a popup (see "Why a redirect, not a popup"
     below), and Google validates this URI exactly against this list.
5. Put the Client ID in `js/config.js` (it's meant to be public — it identifies the app,
   it isn't a secret).

Only the test users you explicitly added can sign in; everyone else gets a clear
"not permitted" screen from Google.

### Why a redirect, not a popup

Sign-in navigates the whole page to Google and back, instead of opening a popup window.
This is deliberate: popups opened with `window.open()` from an app installed via iOS's
"Add to Home Screen" are unreliable — often silently blocked, a well-documented iOS
standalone-mode limitation — which is exactly the failure mode of Google's own
popup-based sign-in library in that context. The full-page redirect works reliably
everywhere `window.open()` doesn't.

Only an explicit tap on "Sync Now" / "Connect Sync Folder" / "Sign In to Sync" ever
triggers this redirect. A background sync (app opened, tab regains focus) never
redirects on its own — if the sign-in has expired, it just reports "Sign-in needed" in
Settings and waits for you to tap something.

### Hosting (GitHub Pages)

Repo → **Settings → Pages** → Source: **Deploy from a branch** → Branch: `main`,
folder: **`/ (root)`**.

## Privacy

Carry-Card collects no analytics and performs no tracking, and has no server of its
own. Camera access is used only to scan barcodes. Your cards never leave your device
unless you connect a Drive folder — after that, sync talks directly to Google, using
your own Google account, not any account or service of Carry-Card's. See
[PRIVACY.md](PRIVACY.md) for the full policy.
