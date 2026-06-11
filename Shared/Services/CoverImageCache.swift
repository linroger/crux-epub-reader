import Foundation
import SwiftUI
import ImageIO

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// In-memory cache for book cover thumbnails.
///
/// Designed for the library grid/list which can display many covers at once.
/// Holding full-resolution raw `Data` in every row causes severe memory
/// pressure on large libraries; this cache hands back appropriately sized
/// `PlatformImage` instances with a bounded count limit.
///
/// The cache is backed by `NSCache` so the OS can purge entries under
/// memory pressure.
actor CoverImageCache {
    static let shared = CoverImageCache()

    private let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 200          // ~200 cached thumbnails
        cache.totalCostLimit = 64 * 1024 * 1024  // 64 MB ceiling
        return cache
    }()

    private init() {}

    /// Get a thumbnail for the given book.
    /// Returns the cached image if available, otherwise generates a new one,
    /// caches it, and returns it.
    func thumbnail(for bookId: UUID, data: Data, targetSize: CGSize) -> PlatformImage? {
        let key = cacheKey(bookId: bookId, size: targetSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = resized(data: data, target: targetSize) else { return nil }

        let cost = Int(targetSize.width * targetSize.height * 4)  // RGBA estimate
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Invalidate cached thumbnails for a specific book (e.g. when cover changes).
    func invalidate(bookId: UUID) {
        let prefix = "\(bookId.uuidString)-"
        // NSCache doesn't expose its keys, so we can only clear all when we
        // need to invalidate one entry's whole family. In practice covers
        // rarely change, so this is acceptable.
        _ = prefix  // documented intent; we clear the whole cache below
        cache.removeAllObjects()
    }

    /// Drop all cached entries (e.g. on theme change or low memory).
    func purge() {
        cache.removeAllObjects()
    }

    // MARK: - Private helpers

    private func cacheKey(bookId: UUID, size: CGSize) -> NSString {
        "\(bookId.uuidString)-\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private func resized(data: Data, target: CGSize) -> PlatformImage? {
        // Downsample with ImageIO rather than decoding the full-resolution
        // cover and redrawing it. CGImageSourceCreateThumbnailAtIndex decodes
        // straight to a thumbnail bounded by `maxPixelSize`, so memory stays
        // bounded even for a pathologically large cover (e.g. a 6000×6000 PNG
        // that would otherwise allocate ~140 MB just to be shrunk to a row).
        let maxPixelSize = Int(max(target.width, target.height).rounded())
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        #if os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}

/// SwiftUI helper that renders a cached cover thumbnail asynchronously.
///
/// Replaces the common pattern of constructing a full-size `NSImage`
/// inline in every row, which inflates memory and re-decodes the same
/// data repeatedly.
struct CachedCoverView: View {
    let bookId: UUID
    let data: Data?
    let size: CGSize
    var cornerRadius: CGFloat = 4

    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                #else
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                #endif
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: data) {
            await load()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: min(size.width, size.height) * 0.4))
                    .foregroundStyle(.white.opacity(0.7))
            }
    }

    private func load() async {
        guard let data else {
            image = nil
            return
        }
        // Scale for retina without baking in a specific factor.
        let scaled = CGSize(width: size.width * 2, height: size.height * 2)
        let result = await CoverImageCache.shared.thumbnail(
            for: bookId,
            data: data,
            targetSize: scaled
        )
        await MainActor.run { self.image = result }
    }
}
