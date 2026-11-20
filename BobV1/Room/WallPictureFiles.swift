//
//  WallPictureFiles.swift
//  The wall picture's own copy of the photo: Documents/Wall/pic-<id>.jpg, cut to the picture's shape, at most 1024 px on the long edge (never scaled up).
//  Nothing is created until a picture is hung. "New game" removes the folder (StartFlow.wipeAll).
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated enum WallPictureFiles {
    static let maxEdge = 1024
    static var folder: URL { URL.documentsDirectory.appending(path: "Wall", directoryHint: .isDirectory) }
    static func url(_ file: String) -> URL { folder.appending(path: file) }

    /// Reads an image file (an album photo) at full size.
    static func image(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: false] as CFDictionary)
    }

    /// Cuts the crop window out of `source`, scales it down to at most `maxEdge`, writes it as a JPEG and returns the file name (nil when it could not be written).
    @discardableResult
    static func bake(source: CGImage, shape: WallShape, crop: WallCrop, in dir: URL = folder) -> String? {
        let size = CGSize(width: source.width, height: source.height)
        let r = crop.rect(imageSize: size, aspect: shape.aspect).integral.intersection(CGRect(origin: .zero, size: size))
        guard r.width >= 2, r.height >= 2, let cut = source.cropping(to: r) else { return nil }
        let k = min(1, CGFloat(maxEdge) / max(r.width, r.height))
        let w = max(Int((r.width * k).rounded()), 1), h = max(Int((r.height * k).rounded()), 1)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cut, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "pic-\(UUID().uuidString.prefix(8).lowercased()).jpg"
        guard let dest = CGImageDestinationCreateWithURL(dir.appending(path: name) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? name : nil
    }

    static func remove(_ file: String, in dir: URL = folder) { try? FileManager.default.removeItem(at: dir.appending(path: file)) }
    static func removeAll() { try? FileManager.default.removeItem(at: folder) }
}
