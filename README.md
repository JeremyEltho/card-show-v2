# CardShow Pro — Setup

iOS-only Pokémon card scanning + inventory app. Runs entirely on-device — no backend, no server, no login.

## Prerequisites

- macOS with **Xcode 16+** (free, Mac App Store)
- A **free Apple ID** added to Xcode (Settings → Accounts → "+")
- An **iPhone** running iOS 17+ for real testing (the iOS simulator can't open the camera, so scanning only works on a physical device)

## Running it

```bash
git clone https://github.com/JeremyEltho/card-show-v2-ios.git
cd card-show-v2-ios
open ios/CardShowPro.xcodeproj
```

In Xcode:

1. Select the `CardShowPro` scheme and your plugged-in iPhone as the destination.
2. Click the project → **Signing & Capabilities** → pick your Team. Bundle ID can be anything that starts with `com.<yourname>.`.
3. Hit **Run** (⌘R). First build installs and launches on the device.

> The free Apple ID re-sign expires after 7 days — just re-run from Xcode to refresh.

## What's in the repo

| Path | What it is |
|---|---|
| `ios/` | SwiftUI app — camera scanner, on-device fuzzy match, SwiftData inventory, receipt export |
| `docs/ARCHITECTURE.md` | As-built architecture doc (scanner pipeline, state machine, persistence layer) |
| `tools/generate_icon.swift` | Regenerates the 1024×1024 app icon (run `swift tools/generate_icon.swift`) |

## How the app works

- **Card identification** runs entirely on-device. Vision framework does OCR; a bundled 4,400-name canonical dictionary backs a Jaro-Winkler fuzzy matcher.
- **Pricing + canonical metadata** is enriched via [pokemontcg.io](https://pokemontcg.io/) directly from the device when in "with receipt" mode. Fast mode skips that round-trip.
- **Inventory** lives in SwiftData on the device. No cloud, no sync, no account.
- **Receipts** are rendered locally and saved straight to your Photos library.

### Optional: pokemontcg.io API key

Free API works without a key but is rate-limited. To raise the limit, drop your key into `Info.plist` as `POKEMONTCG_API_KEY` (the app reads it on launch). Get a free key at [pokemontcg.io](https://pokemontcg.io/).
