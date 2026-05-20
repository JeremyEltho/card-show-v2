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
    private let processingInterval: TimeInterval = 0.5
    private var isProcessing = false

    private let network = NetworkService.shared

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

        // Stage 5: Local fuzzy match
        if let match = FuzzyMatcher.shared.match(ocrText) {
            await finalize(match)
            return
        }

        // Stage 6: Backend fallback
        let backendMatch = try? await fetchFromBackend(ocrText: ocrText)
        if let match = backendMatch {
            await finalize(match)
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

    private func fetchFromBackend(ocrText: String) async throws -> CardMatch? {
        struct ScanReq: Encodable { let ocr_text: String; let ocr_confidence: Float }
        struct ScanResp: Decodable {
            let card_id: String; let name: String; let set_name: String?
            let number: String?; let image_url_sm: String?
            let confidence: Float; let market_price: Double?; let pipeline: String
        }
        let resp: ScanResp = try await network.post("/scan/identify", body: ScanReq(ocr_text: ocrText, ocr_confidence: 0.5))
        return CardMatch(
            cardId: resp.card_id, name: resp.name, setName: resp.set_name,
            number: resp.number, imageUrlSm: resp.image_url_sm,
            confidence: resp.confidence, marketPrice: resp.market_price, pipeline: resp.pipeline
        )
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CardScannerService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        Task { await processFrame(sampleBuffer) }
    }
}
