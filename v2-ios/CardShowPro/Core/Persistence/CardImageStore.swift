import Foundation
import UIKit

/// Disk store for captured card photos. Each image is saved as a JPEG under
/// `<Documents>/card_images/<uuid>.jpg`. The stored value on
/// `LocalInventoryItem` is the *relative* filename only — when the OS rewrites
/// the Documents container path on app update, the file is still locatable.
enum CardImageStore {

    private static let folderName = "card_images"
    private static let jpegQuality: CGFloat = 0.85

    /// In-memory cache so SwiftUI views that ask for the same captured photo
    /// on every body re-evaluation don't pay a JPEG-decode-from-disk hit.
    /// NSCache auto-purges under memory pressure; we also cap at a hard
    /// count to keep its working set reasonable.
    private static let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    /// Returns the on-disk directory, creating it if needed.
    private static func directoryURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir,
                                                    withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save a captured UIImage to disk. Returns the relative filename, e.g.
    /// `"5C0FEE9C-…-9C28.jpg"`, suitable for storing on a SwiftData model.
    /// Returns nil if encoding or writing fails.
    @discardableResult
    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: jpegQuality) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        do {
            let url = try directoryURL().appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    /// Load a previously-saved image by its relative filename. Returns nil if
    /// the file is missing or unreadable. Cached in memory after first hit.
    static func load(_ filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        let key = filename as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        do {
            let url = try directoryURL().appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path),
                  let img = UIImage(contentsOfFile: url.path) else {
                return nil
            }
            memoryCache.setObject(img, forKey: key)
            return img
        } catch {
            return nil
        }
    }

    /// Delete the file for an inventory item (called when the item itself is
    /// deleted). Silent if the file is already gone. Evicts the cache entry.
    static func delete(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        memoryCache.removeObject(forKey: filename as NSString)
        do {
            let url = try directoryURL().appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // Directory unavailable — nothing to clean up.
        }
    }
}
