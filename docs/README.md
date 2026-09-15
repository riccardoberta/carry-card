# Carry-Card (web)

An installable Progressive Web App version of Carry-Card — same idea, same UI, no Apple
Developer account needed. Plain HTML/CSS/JS, no build step, no framework.

## Why this exists

The native iOS app syncs through a folder picked via the iOS Files app (works with
iCloud Drive, Google Drive, Dropbox, etc. without ever talking to any provider's API
directly). Safari has never implemented the File System Access API that would make the
same trick possible from a website, so this version syncs directly against the Google
Drive REST API instead, using your own Google sign-in — still no server of Carry-Card's
own, just a direct client ↔ Google Drive connection.

## What's different from the native app

- **Install**: visit the site in Safari → Share → **Add to Home Screen**. No cable, no
  Developer Mode, no 7-day certificate expiry (that limitation is specific to
  unpaid Apple developer signing, and doesn't exist here).
- **Sync**: a Google Drive folder link (paste it in Settings), not the Files picker.
- **Storage**: IndexedDB instead of the app sandbox — same local-first design, same
  merge algorithm (see `js/model.js`, a direct port of `CardDatabase.swift`).
- **No screen-brightness boost** on the barcode screen — there's no public web API for
  that, so this is a real, permanent limitation versus the native app.
- **Barcode scanning** uses a JS library (ZXing) over `getUserMedia` instead of
  AVFoundation. Reliable, but generally a notch slower/less robust than the native
  scanner on tricky angles/lighting.

## One-time setup (you, not me)

### 1. Google OAuth Client ID

This app needs its own Google OAuth Web Client ID to sign you into Drive:

1. [Google Cloud Console](https://console.cloud.google.com/) → create a project.
2. **APIs & Services → OAuth consent screen** → User type *External* → fill the
   required fields → **stay in "Testing" publishing status** (don't submit for
   verification — for a personal/family app this is the normal, supported way to use
   it indefinitely) → under **Test users**, add your Google account and anyone else who
   should be able to sign in (e.g. your spouse's).
3. **APIs & Services → Credentials → Create Credentials → OAuth Client ID** → Application
   type **Web application** → under **Authorized JavaScript origins**, add the exact
   origin this site is served from (e.g. `https://<username>.github.io` — no path, no
   trailing slash).
4. Copy the Client ID into `js/config.js`.

Only test users you explicitly added can sign in — everyone else gets a "not verified /
not permitted" screen from Google. That's expected and desired.

### 2. Hosting (GitHub Pages)

Repo → **Settings → Pages** → Source: **Deploy from a branch** → Branch: `main`,
folder: **`/docs`**. The site will be at `https://<username>.github.io/<repo>/`.

That exact URL (origin only, e.g. `https://riccardoberta.github.io`) is what must be
in the OAuth client's Authorized JavaScript origins from step 1.

## Local development

```bash
cd docs
python3 -m http.server 8765
```

Then open `http://localhost:8765`. Google sign-in won't work locally unless you also
add `http://localhost:8765` as an authorized origin on the OAuth client — everything
else (cards, barcodes, the UI) works fully offline without it.

## Files

```text
docs/
  index.html
  manifest.webmanifest   PWA metadata (name, icons, colors)
  sw.js                  offline app-shell cache
  css/app.css
  js/
    model.js             LoyaltyCard shape + the merge algorithm (ported from Swift)
    db.js                IndexedDB wrapper (cards + logo blobs)
    barcodeRender.js      bwip-js wrapper — draws a barcode onto a canvas
    barcodeScan.js        ZXing wrapper — decodes a barcode from the camera
    driveSync.js          Google Drive REST v3 client
    sync.js               sync orchestration (load, merge, write — mirrors SyncService.swift)
    config.js             your Google OAuth Client ID
    app.js                views, routing, all UI wiring
  icons/
```
