# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CardShow Pro is an iOS-only Pokémon card scanning and inventory app for card-show vendors. It runs entirely on-device — no backend, no login. Vendors scan cards at convention booths, log buy/sell/trade transactions, and optionally generate receipts.

- **Swift 5.9, iOS 17+, Xcode 16+**
- **No external package dependencies** — pure Apple frameworks (SwiftUI, SwiftData, Vision, AVFoundation, CoreImage)
- Physical iPhone required for camera testing; the iOS Simulator cannot open the camera

## Build & Run

All development happens in Xcode. There is no CLI build system.

```bash
open v2-ios/CardShowPro.xcodeproj
# Then: select your iPhone as destination → Signing & Capabilities → set your Team → ⌘R
```

The `project.yml` file (XcodeGen spec) documents the project structure but the generated `.xcodeproj` is committed, so XcodeGen is not required to build.

**Optional API key:** Add `POKEMONTCG_API_KEY` to `v2-ios/CardShowPro/Resources/Info.plist` for higher pokemontcg.io rate limits. The app works without it.

**Regenerate the app icon:**
```bash
swift tools/generate_icon.swift
```

## Architecture

### Source Layout

```
v2-ios/CardShowPro/
├── App/               # Entry point, ModelContainer setup, AppState
├── Core/
│   ├── Matching/      # FuzzyMatcher — Jaro-Winkler against bundled JSON dictionary
│   ├── Networking/    # PokemonTCGService — pokemontcg.io API actor; Card/CardMatch structs
│   ├── OCR/           # ImagePreprocessor — CIImage perspective-correct + contrast enhance
│   ├── Persistence/   # SwiftDataModels, InventoryService (@MainActor), CardImageStore
│   └── Vision/        # CardScannerService — AVCapture + VNRecognizeText pipeline
├── Features/
│   ├── Home/          # HomeView — dashboard, recent scans, top holdings
│   ├── Inventory/     # CardDetailView, InventoryViewModel
│   ├── Scanner/       # ScannerView, ScannerViewModel, LogMode, ReceiptMode, overlay/sheet views
│   ├── Settings/      # AppSettings (UserDefaults @Observable singleton), SettingsView
│   ├── History/       # TransactionsView, InventoryRowComponents
│   └── Trades/        # TradeSummarySheet
├── Shared/
│   ├── Components/    # PokemonCardFrame, PriceTag, ReceiptExporter, TransactionReceipt
│   ├── Theme/         # Theme (colors, typography, spacing), HoloShimmer, CardBackPattern
│   └── UI/            # CachedAsyncImage
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── pokemon_names.json   # 5,437-name canonical dictionary for on-device matching
```

### Concurrency & Actor Model

| Component | Isolation | Notes |
|---|---|---|
| `CardScannerService` | `actor` | OCR + matching run under actor serialization |
| `ScannerViewModel` | `@Observable @MainActor class` | All UI state; delegate methods are `nonisolated` and re-enter via `Task { @MainActor in ... }` |
| `InventoryService` | `@MainActor` singleton | All SwiftData reads/writes on `container.mainContext` |
| `PokemonTCGService` | `actor` | NSCache (countLimit: 200) prevents redundant API calls per session |
| `FuzzyMatcher` | plain `final class` singleton | Thread-safe after `preload()` (called once in `CardShowProApp.init()` via `Task.detached`) |

The camera delegate runs on a dedicated serial queue (`com.pokescan.camera`), declared `nonisolated`. It acquires an `AtomicFlag` (NSLock-backed) before spawning a `Task.detached` that `await`s the actor's `processFrame`. This two-layer gate (atomic flag + `isProcessing + 0.35 s interval` inside the actor) limits processing to ~3 fps from a 30–60 fps capture stream.

### Scan Pipeline (frame → inventory write)

1. **Camera** — `CardScannerService` captures NV12 frames at 1080p portrait.
2. **ROI extraction** — `VNDetectRectanglesRequest` finds a card-shaped rectangle (aspect 0.55–0.85). If found, `ImagePreprocessor.perspectiveCorrect` + `cropTitleBand` slices the top 25% of the corrected image. If not found, a hard-coded band (horizontal 12%–88%, vertical 68%–86% of frame height) is used instead — aligned with the amber guide frame on screen.
3. **Contrast enhance** — `CIColorControls` (saturation 0, contrast 1.5, brightness +0.05).
4. **OCR** — `VNRecognizeTextRequest` (`.accurate`, `usesLanguageCorrection: true`, `"en-US"`). Results joined with `"\n"`.
5. **Fuzzy match** — `FuzzyMatcher.match(_:)`: extract candidates → Jaro-Winkler scan against `canonicalLower` (pre-lowercased, cached lengths) → confidence threshold (≥ 0.82 to pass, ≥ 0.80 minimum after scanner floor).
6. **Confidence floor** — scanner drops matches below `0.80` (rect path) or `0.92` (no-rect path) before ever calling the delegate.
7. **API enrichment** (with-receipt mode only) — `PokemonTCGService.lookup(name:)` fills `cardId`, `imageUrlSm`, and `marketPrice`. Failure is non-fatal; the local `CardMatch` is used as-is.
8. **State transition** — `ScannerViewModel.handleMatch` sets `scanState = .awaitingConfirmation(match)` for ≥ 0.80, `manualAssist(hint)` for < 0.80. The confirmation sheet is always shown so the vendor can set the actual price.
9. **Log** — `InventoryService.shared.add(...)` on `@MainActor` writes to SwiftData. Captured `UIImage` is saved to `Documents/card_images/<uuid>.jpg` via `CardImageStore`.

### State Machine (`ScanState`)

```
.idle → .scanning
.scanning → .awaitingConfirmation(match)   // ≥ 0.80 confidence
.scanning → .manualAssist(hint)            // < 0.80 (rare; scanner floor makes this nearly unreachable)
.awaitingConfirmation → .scanning          // confirmed or dismissed
.scanning → .tradeReview                   // trade mode: both cards captured
.tradeReview → .scanning                   // committed or cancelled
```

`.autoConfirmed` is declared but never assigned in the live scan path.

### Trade Mode

`TradeBuilder` (owned by `ScannerViewModel`) is a two-slot accumulator. First confirmed match fills `giveCard`; second fills `getCard` and transitions to `.tradeReview`. `TradeSummarySheet` handles the cash-adjustment step and calls `vm.commitTrade()`, which writes both sides as `status = "traded"` with a shared `tradeId` UUID.

### Persistence

- **SwiftData** (`LocalInventoryItem`, `OfflineOperation`) — device-only, `container.mainContext`, no background contexts. The only declared index is `@Attribute(.unique)` on `id` and `clientId`. All status/date filtering happens in Swift after `fetchAll()`.
- **CardImageStore** — JPEG captures at 0.85 quality, stored by relative filename under `Documents/card_images/`. `LocalInventoryItem.capturedImagePath` holds the filename. NSCache (countLimit: 60) dedupes decode overhead.
- **AppSettings** — `UserDefaults`-backed `@Observable` singleton for vendor name, active show, scan defaults, and daily revenue target.

### UI / Theme

All styling flows through `Theme` (`Shared/Theme/Theme.swift`): felt-green surfaces, monospaced price numerics, holographic shimmer on the primary LOG button, rubber-stamp `StatusPill` marks. Use `Theme.Colors.*`, `Theme.Typography.*`, and `Theme.Spacing.*` — do not introduce raw color literals or `Font` values outside the theme. Apply the `.surfaceCard()` view modifier for consistent card-surface backgrounds.

Image loading uses `CachedAsyncImage` (a lightweight wrapper around `AsyncImage`) rather than `AsyncImage` directly. Prefer local `CardImageStore.load(item.capturedImagePath)` before falling back to the remote `cardImageUrl`.

## Key Invariants

- `InventoryService` must only be called from `@MainActor` context.
- `FuzzyMatcher` is safe to call from any thread after `preload()` returns.
- Never call `AVCaptureSession.startRunning()` on the main thread.
- `LogMode.inventoryStatus` is the canonical source for the `status` string stored in SwiftData (`"bought"`, `"sold"`, `"traded"`, `"holding"`).
- Card images are stored by **relative filename**, not absolute path — always reconstruct the full URL via `CardImageStore.load(_:)`.
