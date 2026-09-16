# Carry-Card Privacy Policy

_Last updated: September 2026_

Carry-Card is designed to collect nothing. It has no server, no account system, and no
analytics of any kind.

## What Carry-Card stores

Your loyalty cards (merchant name, code, barcode type, and an optional logo image and
color) are stored **only in your browser**, using IndexedDB — the same local storage
mechanism any website uses, scoped to this app and this device. Nothing is sent
anywhere unless you explicitly connect a sync folder (see below).

## Optional synchronization

If you choose to sync, you paste a link to a folder you already own or were shared in
your own Google Drive, and sign in with your own Google account. From that point,
Carry-Card reads and writes card data directly to Google's Drive API, authenticated as
you — Carry-Card has no server of its own in this exchange; it's a direct connection
between your browser and Google. Google's own privacy practices govern data stored in
your Drive.

If you never connect a sync folder, no data ever leaves your device.

## Camera access

Camera access is requested only when you tap "Scan Barcode" to add or edit a card. The
camera feed is processed on-device (in your browser) to decode the barcode and is never
recorded, stored, or transmitted anywhere.

## Analytics and tracking

Carry-Card contains no analytics scripts, no crash reporters, no advertising
identifiers, and no tracking of any kind. Nothing about your use of the app is
collected, because nothing is collected in the first place.

## Third-party code

The barcode rendering and scanning libraries (bwip-js and ZXing) run entirely in your
browser and are bundled with the app itself — they don't make network requests or
report anything back anywhere.
