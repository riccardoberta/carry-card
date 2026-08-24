# Carry-Card

A deliberately simple loyalty-card wallet for iPhone, built natively with Swift and SwiftUI.

> Open the app → see your loyalty cards → tap one → show a barcode ready to scan.

No payments, no accounts, no login, no server. Carry-Card stores everything locally on
your device and, optionally, syncs it through a folder you choose via the standard iOS
Files interface — iCloud Drive, Google Drive, Dropbox, or any other File Provider.

## Features

- **Instant wallet view.** The card list is the first thing you see. Tap a card to get a
  large, high-contrast barcode ready to scan at checkout.
- **Scan to add.** Point the camera at a barcode (AVFoundation) and the value/type are
  captured and remain editable before saving.
- **Local-first.** Every card lives in `Application Support/CarryCardData/` on-device.
  The app works fully offline; sync is optional and additive.
- **Optional sync, no cloud API.** Pick any folder through Apple's document picker and
  Carry-Card keeps it in step — the same mechanism works for iCloud Drive, Google Drive,
  Dropbox, or a local File Provider, since the app only ever talks to the folder through
  security-scoped bookmarks, never a provider-specific API.
- **Deterministic merge.** Two devices editing the same card resolve by last-write-wins;
  deletions propagate via tombstones; a missing or unreadable remote folder never erases
  local data.
- **Privacy by construction.** No analytics, no tracking, no accounts. Camera and photo
  library access are requested only when the corresponding feature is used.

## Requirements

- Xcode 16 or later
- iOS 17.0+ (device or simulator)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to (re)generate the `.xcodeproj` after
  editing `project.yml`: `brew install xcodegen`

## Getting started

```bash
git clone https://github.com/riccardoberta/carry-card.git
cd carry-card
open CarryCard.xcodeproj
```

The `.xcodeproj` is committed and ready to open directly. If you change `project.yml`,
regenerate it with:

```bash
xcodegen generate
```

### Running on your own iPhone

1. In Xcode: **Settings → Accounts** → sign in with your Apple ID.
2. In `project.yml`, set `DEVELOPMENT_TEAM` (under `settings.base`) to your own team ID
   — find it in Xcode's Accounts settings after signing in, or just select your team once
   in **Signing & Capabilities** and copy the ID it fills in. It's committed in
   `project.yml` (currently set to the original author's) purely so command-line builds
   don't need Xcode open to pick a team; `xcodegen generate` will otherwise overwrite
   whatever you select in the Xcode UI on the next run.
3. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to something under your own
   reverse-DNS prefix (it currently ships as `com.riccardoberta.CarryCard`), then
   `xcodegen generate`.
4. Plug in your iPhone, select it as the run destination, and press ⌘R.
5. On first launch, enable **Developer Mode** on the device if prompted
   (Settings → Privacy & Security → Developer Mode), and trust the developer certificate
   under Settings → General → VPN & Device Management.

### Tests

```bash
xcodebuild -project CarryCard.xcodeproj -scheme CarryCard \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

38 unit tests cover Codable round-tripping, the sync merge algorithm (including
tombstones and edit-after-delete), local persistence and corruption recovery, barcode
symbology serialization, and the security-scoped bookmark lifecycle.

## Architecture

```text
Carry-Card
    ↓
iOS Files / File Provider
    ↓
iCloud Drive · Google Drive · Dropbox · …
```

Carry-Card never speaks to a cloud provider's API directly — it only ever holds a
security-scoped bookmark to a folder the user picked through Apple's document picker.
Whichever provider is behind that folder is invisible to the rest of the app.

```text
CarryCard/
    App/            Composition root (CarryCardApp.swift)
    Models/         LoyaltyCard, BarcodeType, CardDatabase, DeletedCard, AppSettings
    Views/          SwiftUI screens (list, detail, editor, scanner, settings)
    ViewModels/      CardListViewModel, CardEditorViewModel
    Services/       CardStore, ImageStore, BarcodeService, BarcodeScannerService,
                    SyncFolderManager, SyncService
    Utilities/      CodableColor, ImageUtilities, JSONCoding, OneDBarcodeEncoder
    Resources/      Assets.xcassets (AppIcon, AccentColor)

CarryCardTests/     38 unit tests (Swift Testing)
```

State management is `ObservableObject` + `@Published` throughout, injected via
`@EnvironmentObject` from a single composition root. Filesystem work runs off the main
actor through two Swift actors (`CardStore`, `ImageStore`); the whole target builds
clean under Swift 6's complete concurrency checking.

### Barcode rendering

Core Image's built-in generators cover QR, Code 128, PDF417 and Aztec. Core Image has no
generator for EAN-13, EAN-8, UPC-E, Code 39 or Code 93, so `OneDBarcodeEncoder` builds
those from the published module tables into an explicit bar/space bitstring, which
`BarcodeService` then rasterizes with nearest-neighbor scaling — never smoothed — so bar
edges stay sharp for retail scanners.

### Sync & conflict resolution

`CardDatabase.merged(with:)` is a pure, order-independent function: newer `updatedAt`
wins per card, a deletion tombstone beats an older edit, and an edit made *after* a
deletion restores the card. A missing or unreadable remote file is treated as empty,
never as an instruction to erase local data — a sync attempt either fully succeeds
(local and remote both end up holding the merged state) or fully fails, leaving local
data untouched.

## Privacy

Carry-Card collects no analytics and performs no tracking. There is no server to send
data to. Camera access is used only to scan barcodes; photo library access is used only
to choose a logo. Both are requested at the moment the feature is used, not on launch.

## License

No license has been chosen yet — all rights reserved by default until one is added.
