//
//  ThumbnailCache.swift
//  menuai
//
//  A view body only ever asks the cache. The disk read and the JPEG decode
//  happen once, off the main thread, and ImageIO decodes only the pixels a
//  card's image panel can show rather than the full 600px file — a body can be
//  evaluated many times a second while a list is scrolling, and the first
//  draw of a screen with twenty thumbnails should not decode twenty bitmaps.
//
//  NSCache rather than a plain dictionary so the images are evicted under
//  memory pressure instead of growing without limit.
//

import ImageIO
import UIKit

nonisolated enum ThumbnailCache {
    // NSCache is thread-safe; it is shared between the caller and the
    // detached decode.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    /// The largest edge a thumbnail is decoded at: a media card's 96pt photo
    /// at 3x, with a little to spare.
    private static let maxPixelSize = 360

    /// Cache lookup only, no disk. Cheap enough to call from a view body.
    static func cached(_ name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        return cache.object(forKey: name as NSString)
    }

    /// Decodes the thumbnail off the main thread, downsampled to what a cell
    /// draws, and caches it. Returns nil when the file is missing.
    static func load(_ name: String) async -> UIImage? {
        guard !name.isEmpty else { return nil }
        if let cached = cache.object(forKey: name as NSString) { return cached }

        let url = ScanStore.thumbnailURL(named: name)
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            // The saved JPEGs carry no embedded thumbnail, so one has to be
            // made from the image; without `FromImageAlways` this returns nil.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value

        if let image { cache.setObject(image, forKey: name as NSString) }
        return image
    }

    static func forget(_ name: String?) {
        guard let name else { return }
        cache.removeObject(forKey: name as NSString)
    }
}
