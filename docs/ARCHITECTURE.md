# CardShowPro — Architecture Document (As-Built)

> Scope: ingestion path from camera frame → OCR → fuzzy match → state transition → SwiftData write. Derived strictly from the Swift source in `ios/CardShowPro/`.

---

## 1. Concrete Concurrency & Threading Model

### 1.1 Actor topology

| Component | Isolation | File |
|---|---|---|
| `CardScannerService` | `actor` (custom) | `Services/CardScannerService.swift:12` |
| `ScannerViewModel` | `@Observable` class, not `@MainActor`-isolated at the type level | `ViewModels/ScannerViewModel.swift:23` |
| `InventoryService` | `@MainActor` singleton | `Services/InventoryService.swift:6` |
| `FuzzyMatcher` | plain `final class` singleton (no actor) | `Utilities/FuzzyMatcher.swift:20` |
| `ImagePreprocessor` | `struct` with `static` methods, no isolation | `Utilities/ImagePreprocessor.swift:6` |

### 1.2 Camera capture session

- `AVCaptureSession.startRunning()` is dispatched explicitly to `DispatchQueue.global(qos: .userInitiated)` (`CardScannerService.swift:73`) — never the main thread.
- The `AVCaptureVideoDataOutput` sample-buffer delegate runs on a dedicated serial queue: `DispatchQueue(label: "com.pokescan.camera")` (`CardScannerService.swift:42`).
- The delegate method `captureOutput(_:didOutput:from:)` is declared `nonisolated` (`CardScannerService.swift:207`), meaning it runs on that camera queue, **not** on the actor.
- For each frame, the delegate hops onto the actor via `Task.detached(priority: .userInitiated)` which `await`s `self.processFrame(buffer)` (`CardScannerService.swift:217-221`). `processFrame` is actor-isolated, so OCR + matching execute under actor serialization.

### 1.3 Frame gating (two-layer)

A **synchronous, lock-based gate** sits in front of the actor hop, plus an internal actor-state guard:

1. `AtomicFlag` (`CardScannerService.swift:227-243`) — `NSLock`-protected `Bool inFlight`. `frameGate.tryAcquire()` returns `false` if a previous frame is still in flight, and the delegate `return`s immediately without spawning a Task. This prevents `Task` flooding from the 30-60 fps capture stream.
2. Once inside the actor, `processFrame` checks `!isProcessing` **and** `Date().timeIntervalSince(lastProcessedTime) > 0.35` (`CardScannerService.swift:21, 84-89`). The `defer { isProcessing = false }` ensures the flag is cleared on every exit.

The atomic flag is annotated `nonisolated(unsafe)` (`CardScannerService.swift:26`) because it's read from the non-actor delegate queue.

### 1.4 Vision OCR threading

Both `VNDetectRectanglesRequest` and `VNRecognizeTextRequest` are wrapped in `await withCheckedContinuation { ... }` (`CardScannerService.swift:156-179` and `181-200`). `VNImageRequestHandler.perform([request])` is called **synchronously inside the continuation**, blocking the actor's executor for the duration of the Vision request. There is no `qos`/`usesCPUOnly` configuration — Vision picks its own execution context (GPU/NE/CPU).

### 1.5 SwiftData threading

`InventoryService` is marked `@MainActor` (`InventoryService.swift:6`). All writes (`add`, `update`, `delete`, `markSold`) and the read (`fetchAll`) happen on the main actor against `container.mainContext` (`InventoryService.swift:16`). There is no background context.

The `ModelContainer` is constructed once in `CardShowProApp.container`'s lazy initializer and wired into `InventoryService` via `Task { @MainActor in InventoryService.shared.attach(container: c) }` (`App/CardShowProApp.swift:10-16`).

`ScannerViewModel.logCard` invokes inventory writes by explicitly hopping to the main actor: `await MainActor.run { InventoryService.shared.add(...) }` (`ScannerViewModel.swift:152-160`).

### 1.6 Delegate callbacks back to the UI

`CardScannerService` invokes `scannerDidMatch` and `scannerDidUpdateOverlay` by snapshotting `delegate` into a local `let d = delegate` and dispatching via `await MainActor.run { d?.scannerDidMatch(match) }` (`CardScannerService.swift:98-99`, `151-154`).

On the receiving side, both delegate methods on `ScannerViewModel` are declared `nonisolated` and re-enter the main actor via `Task { @MainActor in ... }` (`ScannerViewModel.swift:66-75`).

### 1.7 Startup-time work

`FuzzyMatcher.preload()` runs in `Task.detached(priority: .userInitiated)` (`FuzzyMatcher.swift:85-89`) called from `CardShowProApp.init()` (`App/CardShowProApp.swift:21`). This forces JSON parsing + map construction off the main thread before the first scan.

---

## 2. Camera Capture & Vision OCR Implementation

### 2.1 `AVCaptureSession` configuration

| Setting | Value | Source |
|---|---|---|
| `sessionPreset` | `.hd1920x1080` | `CardScannerService.swift:31` |
| Device | `AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)` | `:33` |
| Output pixel format | `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` (NV12, full-range) | `:41` |
| Delegate queue | Serial: `com.pokescan.camera` | `:42` |
| Frame-rate cap (effective) | ~3 fps (`processingInterval = 0.35` s) | `:21, 84-85` |
| `alwaysDiscardsLateVideoFrames` | **Not set** (defaults to `true`) | — |

**Orientation forcing.** Both the output's video connection and the preview layer's connection are rotated to portrait. iOS 17+ uses `connection.videoRotationAngle = 90` if `isVideoRotationAngleSupported(90)`; pre-17 falls back to `connection.videoOrientation = .portrait` (`CardScannerService.swift:49-69`).

### 2.2 Frame-drop logic

Two independent gates drop frames:

1. **`AtomicFlag.tryAcquire()`** in the capture delegate (`:214`) — non-blocking, returns false if a previous Task is still running. Frame is discarded silently.
2. **Time + state guard** inside the actor (`:84-89`):
   ```
   guard !isProcessing,
         Date().timeIntervalSince(lastProcessedTime) > 0.35,
         let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
   ```

No `CMSampleBuffer` copying is performed — the buffer reference is captured by the detached Task (`:216-219`).

### 2.3 Region-of-Interest math

ROI selection depends on whether `VNDetectRectanglesRequest` returned a card-shaped rectangle:

**Path A — rectangle detected.** `ImagePreprocessor.perspectiveCorrect` applies `CIPerspectiveCorrection` using the four `VNRectangleObservation` normalized corners scaled to image pixels (`ImagePreprocessor.swift:7-19`). Then `cropTitleBand` slices the **top 25%** of the corrected image:

```
crop = CGRect(x: ext.minX,
              y: ext.maxY * 0.75,
              width: ext.width,
              height: ext.height * 0.25)
```
(`ImagePreprocessor.swift:21-26`). Note: CIImage uses a bottom-origin Y axis, so `ext.maxY * 0.75` is geometrically the top quarter.

**Path B — no rectangle.** A hard-coded band of the raw frame is cropped (`CardScannerService.swift:117-122`):

```
x:      ext.minX + ext.width * 0.12
y:      ext.maxY * 0.68
width:  ext.width * 0.76
height: ext.maxY * 0.18
```

i.e. horizontal central 76% (12%–88%), vertical band from 68%–86% of `maxY`. In portrait screen-space this is the band ~14%–32% from the top of the screen, intentionally aligned with the on-screen amber guide frame.

### 2.4 Rectangle-detection request

`VNDetectRectanglesRequest` (`CardScannerService.swift:156-179`) is configured:

| Property | Value |
|---|---|
| `minimumAspectRatio` | `0.55` |
| `maximumAspectRatio` | `0.85` |
| `minimumSize` | `0.15` |
| `maximumObservations` | `10` |

Post-filter (Swift, not request property): keeps observations where `h/w ∈ [1.1, 1.7]`, `confidence > 0.5`, `w > 0.15`, `h > 0.20`, then picks `.max(by: confidence)`.

### 2.5 Contrast enhancement (pre-OCR)

`ImagePreprocessor.enhanceContrast` runs `CIColorControls` with:

| Key | Value |
|---|---|
| `kCIInputSaturationKey` | `0.0` |
| `kCIInputContrastKey` | `1.5` |
| `kCIInputBrightnessKey` | `0.05` |

Applied to whichever path produced `ocrImage` (`CardScannerService.swift:125`).

### 2.6 `VNRecognizeTextRequest` configuration

(`CardScannerService.swift:181-200`)

| Property | Value |
|---|---|
| `recognitionLevel` | `.accurate` |
| `usesLanguageCorrection` | `true` |
| `recognitionLanguages` | `["en-US"]` |
| `minimumTextHeight` | not set (default) |
| `customWords` | not set |
| `revision` | not set (default for SDK) |

**Result handling.** Observations are sorted by `boundingBox.midY` **descending** (top to bottom in screen-space), then `topCandidates(1).first?.string` is taken from each and joined with `"\n"`. No string-level filtering is performed inside the request callback — all string cleanup happens later in `FuzzyMatcher`.

---

## 3. Local Card Matching & SwiftData Query Architecture

> **Critical clarification:** SwiftData is **not** used as the card-name lookup database. SwiftData stores only the user's inventory (`LocalInventoryItem`) and offline-op queue (`OfflineOperation`). Card name recognition runs entirely in-memory against a bundled JSON dictionary loaded by `FuzzyMatcher`. The two layers are separate.

### 3.1 Raw-text → candidate extraction

`FuzzyMatcher.extractCandidates(from: String)` (`FuzzyMatcher.swift:242-285`) processes the newline-joined OCR output:

1. **Line cleaning** (`cleanLine`, `:287-303`) strips, via regex:
   - `HP\s*\d+` (case-insensitive)
   - `\d+/\d+` (set numbers like `4/102`)
   - `\b\d{2,4}\b` (bare HP-like numbers)
   - All chars except letters/digits/space/`-`/`'` collapsed to spaces.
2. **Frame-noise prefix strip:** while `words.first` is in the hard-coded `frameNoise` set (`"basic"`, `"stage"`, `"stage 1"`, `"stage 2"`, `"evolves"`, `"single strike"`, `"rapid strike"`, `"fusion strike"`, `"dynamax"`, `"team"`, `"gas"`, `"games"`, `"care"`, `"ex rule"`, `"v rule"`, `"vmax rule"`, `"pokemon"`, `"pokémon"`, `"trainer"`, `"energy"`, `"item"`, `"supporter"`), drop it.
3. **CamelCase decomposition** (`splitCamelCaseGlued`, `:306-331`) splits at:
   - lower→Upper boundaries (`"gasBulbasaur"` → `["gas","Bulbasaur"]`)
   - Upper-Upper-lower triplet boundaries (`"VMAx"` → split before the lowercase)
   - letter↔digit boundaries
4. **Candidate scoring** (`:255-258`):
   - Base scores: full line = 10, individual word = 5, longest camel split = 8, adjacent camel pairs = 6.
   - `+alpha_count`, `+5` if no digits present.
5. Candidates sorted by score descending; duplicates dedup'd by lowercased form.

> The pipeline does **not** parse set numbers, collector numbers, rarity glyphs, HP values, or any other on-card identifier as a positive signal. Those are noise to be stripped. The only identifier extracted is the card name.

### 3.2 Canonical dictionary loading

(`FuzzyMatcher.load`, `:50-81`)

- Bundle resource: `pokemon_names.json` decoded as:
  ```swift
  struct CanonicalDictionary { 
      pokemon_full, pokemon_base, trainers, energy: [String] 
  }
  ```
- Lists are concatenated and deduplicated (first-occurrence wins).
- Three derived structures are built once at init:
  - `normalisedMap: [String: String]` — normalised key → canonical name (O(1) exact lookup).
  - `allCanonical: [String]` — ordered unique list.
  - `canonicalLower: [(lower: String, original: String, length: Int)]` — pre-lowercased + cached length, used to avoid repeated `lowercased()` calls during fuzzy scans.
  - `pokemonBase: Set<String>` — lowercased base names for the ranking bonus.

### 3.3 Normalisation rules

(`FuzzyMatcher.normalise`, `:93-118`)

Sequence of substitutions:
- `@`→`a`, `€`→`e`, `•`/`·`→`""`, `|`→`I`, `rn`→`m`, `vv`→`w`, `VV`→`W`
- Letter-bounded `0`→`o`, `1`→`l` (only when both neighbouring chars are letters — see `applyBetweenLetters`, `:120-135`)
- Non-alphanumeric (except space/`-`/`'`) → space
- Whitespace collapsed
- Lowercased

### 3.4 Validation pipeline

`FuzzyMatcher.validate(_:)` (`:148-204`):

**Stage 1 — exact lookup.** `normalisedMap[normalised]`. Returns `confidence: 1.0, source: "exact"`.

**Stage 2 — reject too-short inputs.** Reject if `normalised.count < 4` or `alphaCount < 4`.

**Stage 3 — Jaro-Winkler scan with length prefilter.**
- `inputLen = normalised.count`
- `minLen = max(3, (inputLen * 2) / 5)` (≈ inputLen / 2.5)
- `maxLen = (inputLen * 5) / 2` (2.5×)
- Iterate `canonicalLower`; skip entries outside `[minLen, maxLen]`.
- `jaroWinkler(normalised, entry.lower)` — hand-rolled implementation (`:351-384`) with prefix bonus `0.1 * prefix * (1 - jaro)`, prefix capped at 4 chars.
- **Bidirectional length ratio guard:** if `min(inputLen, entry.length) / max(...) < 0.5` AND `score < 0.95`, skip.
- Early break on `score ≥ 0.98`.

**Stage 4 — threshold.** Must be `bestScore ≥ 0.82` to be considered a match.

**Stage 5 — ranking bonuses** (`applyRankingBonus`, `:335-347`):
- `+0.08` if input matches a base Pokémon name exactly.
- `+0.05` if input equals any space-split word in the canonical name (and length ≥ 4).
- `-0.10` if input contains any triple-repeated character.
- Clamped to `[0, 1]`.

### 3.5 Best-of-N over OCR candidates

`FuzzyMatcher.bestMatch(from:)` (`:208-218`) calls `validate` on each ordered candidate, keeps the highest-confidence `matched` result, and short-circuits on `≥ 0.95`.

`FuzzyMatcher.match(_:)` (`:222-237`) is the pipeline entry: extract → bestMatch → wrap in `CardMatch` with `cardId: ""`, `pipeline: result.source`. The `cardId` is later filled in by `PokemonTCGService.shared.lookup(name:)` if the remote enrichment call succeeds (`CardScannerService.swift:142-148`).

### 3.6 SwiftData schema and queries (inventory layer)

**Schema** (`Persistence/SwiftDataModels.swift`):

- `LocalInventoryItem` (`:4-66`)
  - `@Attribute(.unique) var id: UUID`
  - String-typed: `cardId`, `cardName?`, `cardImageUrl?`, `status`, `condition`, `setName?`, `notes?`, `sourceLocation?`, `paymentMethod?`, `counterparty?`, `serverItemId?`, `clientId`.
  - Numeric: `quantity: Int`, `purchasePrice/salePrice/marketPrice: Double?`.
  - `acquiredAt: Date`, `syncedToServer: Bool`.
- `OfflineOperation` (`:68-83`): `@Attribute(.unique) clientId: UUID`, `type`, `payloadJson: Data`, `retryCount`, `createdAt`.

**Container** (`App/CardShowProApp.swift:10-16`): single `ModelContainer` with `Schema([LocalInventoryItem.self, OfflineOperation.self])`, `isStoredInMemoryOnly: false`, injected via `.modelContainer(container)`.

**Read query** (`InventoryService.swift:82-91`):
```swift
var descriptor = FetchDescriptor<LocalInventoryItem>(
    sortBy: [SortDescriptor(\.acquiredAt, order: .reverse)]
)
if let s = status {
    descriptor.predicate = #Predicate { $0.status == s }
}
```
This is the **only** read path. There are no indexes declared beyond the `@Attribute(.unique)` on `id`/`clientId`. All other filtering (today's items, status partitioning for the summary) is performed in Swift after `fetchAll()` (`InventoryService.swift:105-131`).

**Writes** are direct `ctx.insert(item)` / mutation + `try? ctx.save()` (`:39-40`, `:48`, `:73`, `:79`). All on `mainContext`, all `@MainActor`.

---

## 4. Confidence-Tiered State Machine

### 4.1 States

`ScanState` enum (`ViewModels/ScannerViewModel.swift:5-21`):

| Case | Payload | Semantics |
|---|---|---|
| `.idle` | — | Initial; before camera start. |
| `.scanning` | — | Active capture; no current match held. |
| `.autoConfirmed(CardMatch)` | match | **Defined but not currently dispatched to** (see §4.4). |
| `.awaitingConfirmation(CardMatch)` | match | Confirmation sheet shown. |
| `.manualAssist(String)` | hint name | Manual entry / search UI. |
| `.error(String)` | message | Camera failure etc. |

Custom `Equatable` (`:13-20`) collapses the case-with-payload variants for equality purposes (`autoConfirmed` and `awaitingConfirmation` are always considered "not equal" via the `default` branch).

### 4.2 Confidence thresholds enforced in `CardScannerService`

Before a `CardMatch` ever reaches the view model, the scanner applies a **detection-aware floor** (`CardScannerService.swift:137-138`):

```swift
let minConfidence: Float = (cardRect != nil) ? 0.80 : 0.92
guard localMatch.confidence >= minConfidence else { return }
```

So matches with confidence below 0.80 (rectangle path) or 0.92 (fallback band path) are **silently dropped** and `scannerDidMatch` is never called. The `.manualAssist(<0.80)` tier described in the project memory is **unreachable from the live scanner** under the rectangle-detection path — the gate is the scanner's floor, not the view model's.

### 4.3 Threshold logic in `ScannerViewModel.handleMatch`

(`ViewModels/ScannerViewModel.swift:77-97`)

```swift
guard !didJustLog, !isPausedAfterLog else { return }
if case .awaitingConfirmation = scanState { return }
if case .manualAssist     = scanState { return }

let confidence = match.confidence
if confidence >= 0.80 {
    scanState = .awaitingConfirmation(match)
} else {
    scanState = .manualAssist(match.name)
}
```

There is a comment block above the branch (`:87-90`) stating the intent: even at ≥0.95 confidence the result sheet is still shown so the vendor can enter the actual paid price (which rarely equals market). **The `.autoConfirmed` case is therefore declared but never assigned in the current code path** — no `>= 0.95` auto-log branch exists in `handleMatch`. The effective live tiers are:

| Effective range (after scanner floor) | Resulting state |
|---|---|
| `0.80 ≤ c` (rect detected) **or** `0.92 ≤ c` (no rect) | `.awaitingConfirmation(match)` |
| Anything below the scanner floor | dropped, never reaches the VM |

The `< 0.80` branch in `handleMatch` (`.manualAssist`) is structurally dead with respect to the live scan stream because the upstream `minConfidence` floor is itself ≥ 0.80. It would only fire if a `CardMatch` were injected via some non-scanner path (currently none exists).

### 4.4 Re-entry guards

`handleMatch` blocks further state transitions while:

- `didJustLog == true` — set after a confirmed log (`:110`), cleared by `continueScanning()` (`:122`) or `undoLastLog()` (`:138`).
- `isPausedAfterLog == true` — set true in `continueScanning` for 2 seconds via `Task.sleep(for: .seconds(2))` (`:127-130`).
- `scanState` is already `.awaitingConfirmation` or `.manualAssist` — prevents new detections from replacing an open sheet.

### 4.5 Confirmation → log → reset cycle

`confirmCard(_:price:condition:status:sourceLocation:)` (`:101-112`):

1. Sets `isLoggingToInventory = true` (with `defer` to reset).
2. Overrides `match.marketPrice` with the user-entered price if provided.
3. Calls `logCard(...)` which hops to `@MainActor` and invokes `InventoryService.shared.add(...)`.
4. Sets `didJustLog = true` and `scanState = .scanning`.

`continueScanning()` clears `didJustLog`/`lastLoggedCard`, sets `scanState = .scanning`, then enters a 2-second `isPausedAfterLog` debounce.

`undoLastLog()` deletes the most recently created `LocalInventoryItem` via `InventoryService.delete(item:)` and resets the flags.

---

## Cross-cutting notes (factual, not editorial)

- **No backend in the live local path.** The local scan pipeline depends only on bundled JSON + on-device Vision. `PokemonTCGService.lookup(name:)` is called for enrichment (image URL, market price, canonical `cardId`) but its failure is non-fatal: `CardScannerService` falls back to the local `CardMatch` (`CardScannerService.swift:142-148`).
- **`@MainActor` boundaries cross three times per scan:** (a) `scannerDidUpdateOverlay` for the bounding-box overlay, (b) `scannerDidMatch` for the match itself, (c) the `MainActor.run` inside `logCard` for the SwiftData write.
- **No cancellation** is wired through the OCR/rectangle continuations; if the actor task is cancelled mid-Vision, the request still completes synchronously inside the `withCheckedContinuation` block before control returns.
