@preconcurrency import AVFoundation
import Vision
import CoreImage
import UIKit

// Delegate protocol for the scanner
protocol CardScannerDelegate: AnyObject {
    func scannerDidMatch(_ match: CardMatch)
    func scannerDidUpdateOverlay(rect: CGRect?, in viewBounds: CGRect)
}

actor CardScannerService: NSObject {
    weak var delegate: (any CardScannerDelegate)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastProcessedTime: Date = .distantPast
    /// One frame per second. Pokémon card scanning doesn't need 30 FPS — the OCR + fuzzy
    /// match is heavy and lower frequency keeps the device cool + responsive.
    private let processingInterval: TimeInterval = 1.0
    private var isProcessing = false

    /// Synchronous gate used by the capture delegate (which runs on a non-actor thread).
    /// Prevents spawning a Task for every camera frame when one's already in flight.
    nonisolated(unsafe) private var frameGate = AtomicFlag()

    // Start camera session
    func startSession() async throws -> AVCaptureVideoPreviewLayer {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw NSError(domain: "PokeScan", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera not available"])
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.pokescan.camera"))
        session.addOutput(output)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.captureSession = session
        self.previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return layer
    }

    func stopSession() {
        captureSession?.stopRunning()
        captureSession = nil
    }

    // Main frame processing
    func processFrame(_ sampleBuffer: CMSampleBuffer) async {
        guard !isProcessing,
              Date().timeIntervalSince(lastProcessedTime) > processingInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        isProcessing = true
        lastProcessedTime = Date()
        defer { isProcessing = false }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Stage 1: Detect card rectangle
        guard let cardRect = await detectCardRectangle(in: ciImage) else {
            let d = delegate
            await MainActor.run { d?.scannerDidUpdateOverlay(rect: nil, in: .zero) }
            return
        }

        // Stage 2: Perspective correction
        let corrected = ImagePreprocessor.perspectiveCorrect(ciImage, rect: cardRect)

        // Stage 3: Crop title band + enhance
        let titleBand = ImagePreprocessor.cropTitleBand(corrected)
        let enhanced = ImagePreprocessor.enhanceContrast(titleBand)

        // Stage 4: OCR
        guard let ocrText = await recognizeText(in: enhanced), !ocrText.isEmpty else { return }

        // Stage 5: On-device fuzzy match against bundled canonical dictionary (5,437 names)
        guard let localMatch = FuzzyMatcher.shared.match(ocrText) else { return }

        // Stage 6: Look up full metadata + market price from pokemontcg.io directly.
        // If the API is unreachable we still return the local match (no price, no image).
        if let api = await PokemonTCGService.shared.lookup(name: localMatch.name) {
            var enriched = api
            enriched.confidence = localMatch.confidence    // preserve scanner confidence tier
            await finalize(enriched)
        } else {
            await finalize(localMatch)
        }
    }

    private func finalize(_ match: CardMatch) async {
        let d = delegate
        await MainActor.run { d?.scannerDidMatch(match) }
    }

    private func detectCardRectangle(in image: CIImage) async -> VNRectangleObservation? {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { req, _ in
                let observations = req.results as? [VNRectangleObservation] ?? []
                let card = observations.filter { ob in
                    let ratio = ob.boundingBox.height / ob.boundingBox.width
                    return (1.2...1.7).contains(ratio) && ob.confidence > 0.7
                        && ob.boundingBox.width > 0.2 && ob.boundingBox.height > 0.2
                }.max(by: { $0.confidence < $1.confidence })
                continuation.resume(returning: card)
            }
            request.minimumAspectRatio = 0.55
            request.maximumAspectRatio = 0.85
            request.minimumSize = 0.15
            try? VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        }
    }

    private func recognizeText(in image: CIImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation])?.first?
                    .topCandidates(1).first?.string
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            try? VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        }
    }

}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CardScannerService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // Synchronous gate — drop the frame immediately if a previous one is still
        // being processed. Without this we'd queue up dozens of Tasks per second
        // and overwhelm the device. The atomic flag is cleared inside processFrame
        // once OCR + fuzzy match complete.
        guard frameGate.tryAcquire() else { return }

        let buffer = sampleBuffer
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.processFrame(buffer)
            self.frameGate.release()
        }
    }
}

// MARK: - Simple atomic flag (used by the non-actor capture delegate)

final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = false

    /// Returns true if the caller acquired the flag, false if it was already set.
    func tryAcquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if inFlight { return false }
        inFlight = true
        return true
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        inFlight = false
    }
}
