# klarna-import

A **one-time** migration tool: your Klarna loyalty cards → Carry-Card's data
format. It is completely independent of the Carry-Card iOS app — you can
delete this entire `tools/klarna-import/` directory after your migration and
Carry-Card will be unaffected.

## Why this approach, and not an API or browser login

Before writing any code, this was investigated:

- Klarna's loyalty-card feature is not Klarna's own — it's **Stocard**,
  which Klarna acquired. Stocard used to offer a real GDPR data export (a
  password-protected ZIP with structured barcode data), but **the standalone
  Stocard app and that export were discontinued on 2025-06-30** ("Stocard is
  now part of Klarna and the migration has closed... all Stocard user data
  has been permanently deleted" — Klarna). The open-source Catima app's
  importer for that format was removed shortly after, for the same reason.
- Klarna's general GDPR data-extract request still exists (via your account,
  or a web form), but it's delivered as an **encrypted PDF** about purchases
  and products used — there is no confirmation it contains structured,
  machine-readable barcode payloads for loyalty cards specifically. It's
  worth requesting anyway (see below) but it is not the primary path here.
- Loyalty cards live in the **Klarna mobile app**. No evidence was found of
  an equivalent klarna.com web page, which means browser automation
  (Playwright et al.) most likely can't even reach the loyalty-cards screen.

**Conclusion:** the safest, simplest, and most reliable method is for *you*
to open the Klarna app on your own phone (already logged in — no credentials
touch this tool at all) and take a screenshot of each card's barcode screen.
This tool then decodes those screenshots **entirely locally and offline**.
Nothing here ever talks to Klarna's servers, so there is no password,
cookie, or token to protect in the first place.

### Optional: also file the official GDPR request

Costs nothing and might back up merchant names even though it likely won't
give reliable barcode payloads: log into your Klarna account (or use
Klarna's data-request web form) and ask for a personal-data export under
Art. 20 GDPR ("data portability"). Expect up to 30 days and an encrypted
PDF. This tool does not need it to work, and does not process it.

## Security

- This tool **never** asks for, stores, or transmits your Klarna
  username, password, cookies, or any token. There is no login step.
- It only ever reads image files you already saved to your Mac yourself.
- It never modifies your real Carry-Card data without an explicit `apply`
  step you run after reviewing a preview (see below).

## 1. Capture your cards

On your phone, open each loyalty card in the Klarna app and screenshot the
barcode screen. Optionally also screenshot/save a clean logo image. Arrange
them like this:

```text
input/
    Esselunga/
        barcode.jpg
    IKEA Family/
        barcode.png
        logo.png            (optional)
    Example Store/
        barcode.jpg
```

- One subfolder per card; the folder name is the initial merchant name
  (you can correct it later).
- The barcode file must start with `barcode` (e.g. `barcode.jpg`,
  `barcode-1.png`). Crop it to just the barcode if you can — a screenshot
  with extra UI chrome around it usually still decodes fine, but a tight
  crop is more reliable.
- The optional logo file must start with `logo`.

## 2. Set up (once)

```bash
cd tools/klarna-import
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 3. Scan → preview (does not touch Carry-Card data)

```bash
klarna-import scan input --carrycard-folder "/path/to/Carry-Card"
```

(Use `python3 -m klarna_import.cli scan ...` instead of `klarna-import` if
you didn't `pip install -e .`.)

`--carrycard-folder` is only used here to detect duplicates against your
existing cards — nothing is written yet. This prints a preview like:

```text
Esselunga
Barcode: 8001234567890
Type: ean13
Logo: found
Duplicate: new
Status: ready

Example Store
Barcode: unknown
Type: unknown
Logo: none
Duplicate: new
Status: needsReview
  note: No barcode detected in the image.

Summary
-------
Cards discovered: 2
Ready to import: 1
Need review: 1
...
```

and writes `input/preview.json` — a full, human-editable intermediate file.

## 4. Fix anything marked `needsReview`

Open `preview.json` in any text editor. For a card that needs review, fix
whatever's wrong directly in the JSON:

- `"code"` — **always a quoted string.** Never remove leading zeros
  (`"0012345"` must stay `"0012345"`, not become `12345`). The scanner
  refuses to load a file where `code` isn't a JSON string, precisely to
  catch this mistake.
- `"barcodeType"` — one of `ean8, ean13, upce, code39, code93, code128, qr,
  pdf417, aztec` (exactly Carry-Card's own list).
- `"status"` — set to `"ready"` once you're confident in the values, or
  leave as `"needsReview"`/set to `"skipped"` to exclude it from `apply`.
- `"duplicate.classification"` — if the tool guessed `possibleDuplicate`
  and you've confirmed by eye that it's actually the same card (or
  definitely not), change it to `"existing"` (with the correct
  `matchedCardId`) or `"new"`.

Only cards with `"status": "ready"` are ever imported by `apply`.

## 5. Apply (writes into your real Carry-Card folder)

```bash
klarna-import apply input/preview.json --carrycard-folder "/path/to/Carry-Card"
```

Before writing anything, this:

1. Loads and validates your existing `cards.json` / `deleted.json`.
2. Copies them (plus `logos/`) into `backup-before-klarna-import/` next to
   your Carry-Card folder. Refuses to run if that backup already exists,
   so you never lose an earlier backup by accident.
3. Builds the merged list in memory, writes it to a temp file, re-parses
   that temp file to confirm it's valid JSON, and only *then* atomically
   replaces the real `cards.json` / `deleted.json`.
4. Copies logos in, resized to Carry-Card's own 512px/JPEG convention.

It never overwrites an existing card's barcode, type, or name — for a
duplicate it only ever *adds* a missing logo. `"possibleDuplicate"` cards
are always skipped, never auto-merged.

A migration report is printed and saved to
`input/klarna-migration-report.txt`.

## Validation limits (read this before trusting a card)

- **EAN-13 / EAN-8 / UPC-E**: fully re-validated. The decoder's own
  checksum check must pass, *and* this tool independently recomputes the
  GS1 check digit using the exact same formulas Carry-Card's Swift renderer
  uses (`CarryCard/Utilities/OneDBarcodeEncoder.swift`). A card only reaches
  `"confidence": "high"` for these types if both agree.
- **Code 128 / Code 39 / Code 93 / QR / PDF417 / Aztec**: validated via the
  decoder's own internal checksum/structure check and requiring exactly one
  unambiguous candidate in the image. This tool has no way to invoke
  Carry-Card's Swift barcode *generator* to do a true render → re-decode
  round trip, so these are marked `"medium"` confidence rather than
  `"high"` even when the decode looks clean. If in doubt, open the card in
  Carry-Card after import and compare its rendered barcode against the
  original Klarna screenshot by eye.
- If a barcode can't be decoded at all, or two are found in one image, the
  card is marked `needsReview` with a note explaining why — it is never
  guessed.

## Cleanup

After a successful migration:

```bash
rm -rf input .venv
```

(`input/`, `preview.json` and the migration report are already gitignored,
since they can contain your personal card data — never credentials.) The
only lasting output is inside your real Carry-Card folder, plus the
`backup-before-klarna-import/` safety copy next to it, which you can delete
once you've confirmed everything imported correctly.

## Running the tests

```bash
source .venv/bin/activate
pip install -r requirements-dev.txt
python3 -m pytest
```

Tests use only synthetically generated barcode images — never real Klarna
data.
