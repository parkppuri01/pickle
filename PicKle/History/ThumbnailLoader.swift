import AppKit
import ImageIO

/// Loads small, downsampled thumbnails off the main thread and caches them.
///
/// Retina screenshots are multi-megabyte; decoding the full-resolution image on
/// the main thread for a ~90pt cell would stutter the grid and balloon memory.
/// ImageIO's thumbnail API decodes straight to the target size, and an NSCache
/// keyed by path+mtime keeps re-scrolls instant.
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, NSImage>()

    /// Returns a downsampled thumbnail (longest side ≈ `maxPixel`), or nil if the
    /// file can't be read as an image. Decoding happens off the main thread.
    static func thumbnail(for url: URL, maxPixel: CGFloat = 320) async -> NSImage? {
        let key = cacheKey(for: url, maxPixel: maxPixel) as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image = await Task.detached(priority: .userInitiated) {
            downsample(url: url, maxPixel: maxPixel)
        }.value

        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static func cacheKey(for url: URL, maxPixel: CGFloat) -> String {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate?.timeIntervalSince1970) ?? 0
        return "\(url.path)|\(mtime)|\(Int(maxPixel))"
    }

    private static func downsample(url: URL, maxPixel: CGFloat) -> NSImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
