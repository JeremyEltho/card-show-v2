import SwiftUI
import UIKit

/// Drop-in replacement for SwiftUI's `AsyncImage` that caches successful
/// downloads in a shared `NSCache`. Stock pokemontcg.io artwork is requested
/// repeatedly across History, scan sheets, recent-scan tiles, etc.; vanilla
/// `AsyncImage` re-fetches every time. This version short-circuits to the
/// cached `UIImage` after the first hit.
///
/// API mirrors the phase-based `AsyncImage(url:content:)` initializer.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content

    init(url: URL?,
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            // `task(id:)` cancels the previous fetch when `url` changes and
            // starts a new one — exactly what we want when a list of rows
            // recycles its image views.
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        if let cached = ImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return }
            guard let img = UIImage(data: data) else {
                phase = .empty
                return
            }
            ImageCache.shared.store(img, for: url)
            phase = .success(Image(uiImage: img))
        } catch {
            if Task.isCancelled { return }
            phase = .failure(error)
        }
    }
}

/// Shared URL → UIImage cache. NSCache auto-purges under memory pressure;
/// we also cap by count and an approximate byte budget so a long History
/// scroll can't blow out memory.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 120
        c.totalCostLimit = 50 * 1024 * 1024 // ~50 MB
        return c
    }()

    private init() {}

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        // Rough byte cost — image bytes if we have them, else fall back to a
        // pixel-count estimate. Lets NSCache evict by `totalCostLimit`.
        let cost: Int = {
            if let data = image.pngData() { return data.count }
            let w = Int(image.size.width * image.scale)
            let h = Int(image.size.height * image.scale)
            return w * h * 4
        }()
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}
