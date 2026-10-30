//
//  ImageProcessing.swift
//  menuai
//

import UIKit

nonisolated enum ImageProcessing {
    /// Claude Opus 5 accepts images up to 2576px on the long edge. Menus are
    /// text-dense, so we send the full allowance rather than downscaling —
    /// small print is exactly what gets lost first.
    static let maxDimension: CGFloat = 2576

    /// Normalises orientation, scales to the vision limit, and JPEG-encodes.
    static func prepareForVision(_ image: UIImage) -> Data? {
        let resized = resized(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: 0.85)
    }

    /// Smaller copy for the saved-scan thumbnails.
    static func thumbnailData(_ image: UIImage) -> Data? {
        resized(image, maxDimension: 600).jpegData(compressionQuality: 0.7)
    }

    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)

        // Still redraw at scale 1 even when small enough, so the EXIF
        // orientation is baked in rather than sent sideways.
        let scale = longEdge > maxDimension ? maxDimension / longEdge : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
