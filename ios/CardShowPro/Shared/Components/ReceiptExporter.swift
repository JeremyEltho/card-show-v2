import SwiftUI
import UIKit

/// Renders a `TransactionReceipt` to a UIImage and saves it to the user's
/// photo library. Caller must already hold (or trigger) photo-add permission
/// — `UIImageWriteToSavedPhotosAlbum` will prompt the system sheet on first
/// use, governed by `NSPhotoLibraryAddUsageDescription` in Info.plist.
@MainActor
enum ReceiptExporter {

    enum ExportError: Error {
        case renderFailed
        case writeFailed(Error)
    }

    /// Render the receipt and save it to Photos.
    /// Returns the rendered UIImage on success (caller can also display it).
    /// When `includeImage` is true, the card artwork is fetched from
    /// `item.cardImageUrl` *before* rendering — ImageRenderer takes a
    /// synchronous snapshot, so AsyncImage alone leaves a placeholder.
    @discardableResult
    static func save(item: LocalInventoryItem, includeImage: Bool = true) async throws -> UIImage {
        // Primary source: the live camera-captured photo of the actual card
        // the user scanned, saved to disk by ScannerViewModel.logCard. Falls
        // back to pokemontcg.io stock art only for legacy entries (no
        // captured photo recorded) or when the file is missing.
        let cardImage: UIImage?
        if includeImage {
            if let local = CardImageStore.load(item.capturedImagePath) {
                cardImage = local
            } else {
                cardImage = await fetchCardImage(from: item.cardImageUrl)
            }
        } else {
            cardImage = nil
        }
        let image = try render(item: item, cardImage: cardImage, includeImage: includeImage)
        try await writeToPhotos(image)
        return image
    }

    // MARK: - Render

    /// Pure-render path — does not touch Photos. Useful if you ever want
    /// share-sheet export or print preview before saving.
    static func render(item: LocalInventoryItem,
                       cardImage: UIImage? = nil,
                       includeImage: Bool = true) throws -> UIImage {
        let view = TransactionReceipt(item: item,
                                      cardImage: cardImage,
                                      includeImage: includeImage)
            .environment(\.colorScheme, .light) // receipt is parchment, not dark
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0   // 1080-wide PNG for a 360pt-wide layout
        guard let rendered = renderer.uiImage else {
            throw ExportError.renderFailed
        }
        // Flatten to an opaque bitmap before handing to Photos. The receipt
        // is visually opaque (parchment background covers everything), and
        // ImageRenderer hands back an RGBA image — Photos warns that the
        // alpha doubles decode-time memory. Flattening to opaque also
        // produces a smaller PNG on disk.
        return flattenOpaque(rendered)
    }

    private static func flattenOpaque(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(at: .zero)
        }
    }

    // MARK: - Image prefetch

    /// Downloads the card artwork synchronously (within the async path) so it
    /// can be passed to ImageRenderer. Failures degrade silently to nil — the
    /// receipt still renders with the no-image layout.
    private static func fetchCardImage(from urlString: String?) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    // MARK: - Photos write

    private static func writeToPhotos(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let writer = PhotosWriter(continuation: cont)
            // Retain the writer until the callback fires.
            writer.retainSelf()
            UIImageWriteToSavedPhotosAlbum(
                image,
                writer,
                #selector(PhotosWriter.didFinishWriting(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        }
    }
}

/// Adapter that bridges the C-style UIImageWriteToSavedPhotosAlbum callback
/// to a Swift async continuation. Retains itself until the callback fires,
/// then releases.
private final class PhotosWriter: NSObject {
    private var continuation: CheckedContinuation<Void, Error>?
    private var selfRef: PhotosWriter?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func retainSelf() {
        self.selfRef = self
    }

    @objc func didFinishWriting(_ image: UIImage,
                                didFinishSavingWithError error: Error?,
                                contextInfo: UnsafeRawPointer?) {
        defer { selfRef = nil }
        if let error {
            continuation?.resume(throwing: ReceiptExporter.ExportError.writeFailed(error))
        } else {
            continuation?.resume(returning: ())
        }
        continuation = nil
    }
}
