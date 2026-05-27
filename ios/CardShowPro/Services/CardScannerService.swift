@preconcurrency import AVFoundation
import Vision
import CoreImage
import UIKit

protocol CardScannerDelegate: AnyObject, Sendable {
    func scannerDidMatch(_ match: CardMatch)
    func scannerDidUpdateOverlay(rect: CGRect?, in viewBounds: CGRect)
}

actor CardScannerService: NSObject {
    weak var delegate: (any CardScannerDelegate)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    /// When true, the scanner trades quality for speed:
    ///   - tighter frame gate (0.20s ≈ 5fps vs 0.35s ≈ 3fps)
    ///   - skip VNDetectRectanglesRequest (~30ms/frame)
    ///   - skip the pokemontcg.io API enrichment call (network round-trip)
    /// The captured photo becomes a centre-crop instead of perspective-
    /// corrected, and the sheet shows no market-price prefill.
    private var fastMode: Bool = false

    /// When true, processFrame returns immediately. Used to halt OCR + Vision
    /// work entirely while a modal sheet is up — saves CPU/GPU that would
    /// otherwise contend with the keyboard while the user is typing prices.
    private var isPaused: Bool = false

    /// Toggle fast mode. Driven by the view model's receiptMode.
    func setFastMode(_ enabled: Bool) {
        fastMode = enabled
        frameGate.setInterval(enabled ? 0.20 : 0.35)
    }

    /// Pause / resume the OCR pipeline. The camera preview stays live (cheap,
    /// hardware-backed) but no Vision work runs while paused.
    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    /// Combined synchronous gate: time-based throttle + in-flight flag.
    /// Lives outside the actor so the capture delegate (running on a non-actor
    /// queue) can probe it without an actor hop. Replaces the old separate
    /// AtomicFlag + `lastProcessedTime` actor state — both checks now happen
    /// synchronously *before* a Task is spawned for the frame.
    nonisolated private let frameGate = FrameGate(interval: 0.35)

    /// Dedicated queue for synchronous Vision work. Keeping a named queue
    /// (instead of a global pool grab) makes traces readable and isolates
    /// OCR latency from any other userInitiated work on the device.
    nonisolated private let visionQueue = DispatchQueue(
        label: "com.cardshowpro.vision",
        qos: .userInitiated
    )

    /// Shared CIContext for rasterising the captured card frame. Creating one
    /// per frame is expensive; reuse it.
    nonisolated private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Camera session

    func startSession() async throws -> AVCaptureVideoPreviewLayer {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw NSError(domain: "CardShowPro", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Camera not available"])
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.cardshowpro.camera"))
        session.addOutput(output)

        // Force portrait orientation on the buffer so OCR cropping sees the card
        // upright. Without this the back camera delivers landscape sensor data
        // (card name on the right edge instead of the top), and crop-the-top
        // logic ends up reading from the side of the card.
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let pConn = layer.connection {
            if #available(iOS 17.0, *) {
                if pConn.isVideoRotationAngleSupported(90) {
                    pConn.videoRotationAngle = 90
                }
            } else if pConn.isVideoOrientationSupported {
                pConn.videoOrientation = .portrait
            }
        }
        self.captureSession = session
        self.previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return layer
    }

    func stopSession() {
        captureSession?.stopRunning()
        captureSession = nil
        // Drop the preview-layer reference too — otherwise we keep holding
        // the old AVCaptureVideoPreviewLayer across scanner re-presentations.
        previewLayer = nil
        // Reset the gate so the next session doesn't inherit an in-flight
        // flag from a frame that was dropped during teardown.
        frameGate.release()
        // Resume scanning by default — pause is per-presentation state.
        isPaused = false
    }

    // MARK: - Frame processing (actor-isolated orchestrator)

    func processFrame(_ sampleBuffer: CMSampleBuffer) async {
        // Skip the whole pipeline if we're paused — typically because a
        // modal sheet (price input, manual assist, trade review) is up and
        // we don't want OCR background work fighting the keyboard.
        guard !isPaused else { return }
        // No need for an `isProcessing` or time check here — `frameGate` already
        // serialised us. Just unwrap the pixel buffer and drive the pipeline.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let isFast = fastMode

        // Stage 1: Rectangle detection. Skipped entirely in fast mode — saves
        // ~30ms per frame at the cost of a less clean captured photo and no
        // on-screen amber bounding box. Normal mode runs detection and uses
        // it for both perspective correction and the overlay.
        let cardRect: VNRectangleObservation?
        if isFast {
            cardRect = nil
        } else {
            cardRect = await detectCardRectangle(in: ciImage)
        }
        let d = delegate
        await MainActor.run { d?.scannerDidUpdateOverlay(rect: cardRect?.boundingBox, in: .zero) }

        // Stage 2: Build the OCR region.
        //   - With a detection: perspective-correct → crop top 25% (title band)
        //   - Without one: crop the area corresponding to the on-screen guide
        //     frame's title band — top 22% of the central 80% of the camera
        //     image (in portrait). Matches roughly where the user places the
        //     card name with the amber guide frame.
        let ocrImage: CIImage
        if let rect = cardRect {
            let corrected = ImagePreprocessor.perspectiveCorrect(ciImage, rect: rect)
            ocrImage = ImagePreprocessor.cropTitleBand(corrected)
        } else {
            let ext = ciImage.extent
            let band = CGRect(
                x: ext.minX + ext.width * 0.12,
                y: ext.maxY * 0.68,
                width: ext.width * 0.76,
                height: ext.maxY * 0.18
            )
            ocrImage = ciImage.cropped(to: band)
        }
        let enhanced = ImagePreprocessor.enhanceContrast(ocrImage)

        // Stage 3: OCR (also off-actor).
        guard let ocrText = await recognizeText(in: enhanced), !ocrText.isEmpty else { return }

        // Stage 4: On-device fuzzy match against bundled canonical dictionary.
        guard let localMatch = FuzzyMatcher.shared.match(ocrText) else { return }

        // Stage 5: Confidence floor. Lowered to 0.40 so the downstream
        // 3-tier router in ScannerViewModel can actually see low-confidence
        // matches and surface them as manual-assist instead of silently
        // dropping them. The router applies the meaningful tiers.
        guard localMatch.confidence >= 0.40 else { return }

        // Stage 5.5: Snapshot the live card photo. If a rectangle was
        // detected, perspective-correct the full card region for a clean,
        // rectangular shot. Otherwise crop the central card-shaped area of
        // the frame (matches the on-screen amber guide). This is the
        // image the receipt exporter will use — not pokemontcg.io stock art.
        let captured = renderCardPhoto(from: ciImage, rect: cardRect)

        // Stage 6: Optional API enrichment from pokemontcg.io.
        // Skipped in fast mode — the network round-trip can dominate the
        // perceived latency on flaky show wifi. The sheet still works
        // without market-price prefill; the receipt uses the captured
        // photo, not stock art.
        if isFast {
            var localWithImage = localMatch
            localWithImage.capturedImage = captured
            await finalize(localWithImage)
        } else if let api = await PokemonTCGService.shared.lookup(name: localMatch.name) {
            var enriched = api
            enriched.confidence = localMatch.confidence
            enriched.capturedImage = captured
            await finalize(enriched)
        } else {
            var localWithImage = localMatch
            localWithImage.capturedImage = captured
            await finalize(localWithImage)
        }
    }

    /// Renders a clean UIImage of the scanned card. Uses perspective
    /// correction when we have a rectangle observation; otherwise crops the
    /// central card-shaped band from the raw frame.
    ///
    /// Output is downsampled so the longest edge is ~800pt — full sensor
    /// resolution is wasted on a card photo viewed at thumbnail size in
    /// receipts and history. Holding multiple full-resolution UIImages
    /// across the scan state machine + tradeBuilder + lastLoggedCard was
    /// putting real memory pressure on the device.
    nonisolated private func renderCardPhoto(from ciImage: CIImage,
                                             rect: VNRectangleObservation?) -> UIImage? {
        let cardCI: CIImage
        if let rect {
            cardCI = ImagePreprocessor.perspectiveCorrect(ciImage, rect: rect)
        } else {
            // No detected rectangle — fall back to the central guide-frame
            // region (the same area the user is asked to align the card to).
            let ext = ciImage.extent
            let guide = CGRect(
                x: ext.minX + ext.width * 0.10,
                y: ext.maxY * 0.18,
                width: ext.width * 0.80,
                height: ext.maxY * 0.64
            )
            cardCI = ciImage.cropped(to: guide)
        }

        // Lanczos downsample to ~800pt max edge. GPU-accelerated via Core
        // Image, no full-res CGImage round-trip needed.
        let extent = cardCI.extent
        let maxEdge = max(extent.width, extent.height)
        let targetMax: CGFloat = 800
        let downsampled: CIImage
        if maxEdge > targetMax {
            let scale = targetMax / maxEdge
            if let filter = CIFilter(name: "CILanczosScaleTransform") {
                filter.setValue(cardCI, forKey: kCIInputImageKey)
                filter.setValue(scale, forKey: kCIInputScaleKey)
                filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
                downsampled = filter.outputImage ?? cardCI
            } else {
                downsampled = cardCI
            }
        } else {
            downsampled = cardCI
        }

        guard let cg = ciContext.createCGImage(downsampled, from: downsampled.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private func finalize(_ match: CardMatch) async {
        let d = delegate
        await MainActor.run { d?.scannerDidMatch(match) }
    }

    // MARK: - Vision (nonisolated — runs off the actor's executor)
    //
    // Both functions are `nonisolated async`. When `processFrame` awaits them,
    // the actor releases its executor and the synchronous Vision work runs on
    // `visionQueue`. The actor can service other messages while the GPU /
    // Neural Engine is busy, and the cooperative thread pool isn't blocked.

    nonisolated func detectCardRectangle(in image: CIImage) async -> VNRectangleObservation? {
        await withCheckedContinuation { (cont: CheckedContinuation<VNRectangleObservation?, Never>) in
            visionQueue.async {
                let request = VNDetectRectanglesRequest()
                request.minimumAspectRatio = 0.55
                request.maximumAspectRatio = 0.85
                request.minimumSize = 0.15
                // Critical: default is 1. Without this, Vision only returns the
                // single best rectangle, which might be the laptop / table edge
                // / keyboard, not the card. Allow up to 10 candidates and we'll
                // filter for the card.
                request.maximumObservations = 10

                do {
                    try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
                } catch {
                    cont.resume(returning: nil)
                    return
                }

                // `perform` is synchronous — by the time it returns, results
                // are populated on the request. No completion-handler race.
                let observations = request.results ?? []
                let card = observations.filter { ob in
                    let h = ob.boundingBox.height, w = ob.boundingBox.width
                    let ratio = h / w
                    return (1.1...1.7).contains(ratio)
                        && ob.confidence > 0.5
                        && w > 0.15 && h > 0.20
                }.max(by: { $0.confidence < $1.confidence })
                cont.resume(returning: card)
            }
        }
    }

    nonisolated func recognizeText(in image: CIImage) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            visionQueue.async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]

                do {
                    try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
                } catch {
                    cont.resume(returning: nil)
                    return
                }

                let observations = request.results ?? []
                // Sort top-to-bottom (largest Y → smallest) and collect ALL
                // recognised lines. The card name might not be the
                // highest-confidence line; the candidate ranker in
                // FuzzyMatcher picks the best one.
                let lines = observations
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CardScannerService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // SYNCHRONOUS gate. Both throttle (timestamp delta) and in-flight
        // checks happen here, on the camera queue, BEFORE we spawn a Task.
        // This means we no longer pay the cost of creating a Task per camera
        // frame just to throw it away inside the actor.
        guard frameGate.tryAcquire() else { return }

        let buffer = sampleBuffer
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.processFrame(buffer)
            self.frameGate.release()
        }
    }
}

// MARK: - FrameGate: synchronous combined throttle + in-flight gate
//
// Owned by `CardScannerService` as a `nonisolated let`. Sendable because all
// mutable state is protected by an internal NSLock.

final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = false
    private var lastProcessedAt: Date = .distantPast
    private var interval: TimeInterval

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Returns true iff:
    ///   - no frame is currently being processed, AND
    ///   - `interval` seconds have elapsed since the last accepted frame.
    /// On success, marks the gate as in-flight and stamps the acceptance time.
    func tryAcquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if inFlight { return false }
        let now = Date()
        if now.timeIntervalSince(lastProcessedAt) <= interval { return false }
        inFlight = true
        lastProcessedAt = now
        return true
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        inFlight = false
    }

    /// Adjust the throttle window. Called when the scanner switches between
    /// receipt mode (slower, 0.35s) and fast mode (snappier, 0.20s).
    func setInterval(_ value: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        interval = value
    }
}
