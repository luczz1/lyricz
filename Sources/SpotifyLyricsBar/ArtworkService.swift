import Foundation
import CoreGraphics
import ImageIO
import LyricsCore

struct AlbumArtwork: Sendable {
    let png: Data
    let palette: AlbumPalette
}

/// Download, thumbnail decoding and palette extraction happen outside the main actor.
actor ArtworkService {
    private var cache: [URL: AlbumArtwork] = [:]
    private var order: [URL] = []

    func load(_ url: URL) async throws -> AlbumArtwork? {
        guard url.scheme == "https" else { return nil }
        if let cached = cache[url] { return cached }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }

        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: 32, height: 32,
                    bitsPerComponent: 8, bytesPerRow: 32 * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        guard rendered else { return nil }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        try Task.checkCancellation()
        let artwork = AlbumArtwork(png: png as Data, palette: AlbumPalette.extract(rgba: pixels))
        cache[url] = artwork
        order.removeAll { $0 == url }
        order.append(url)
        if order.count > 24 { cache.removeValue(forKey: order.removeFirst()) }
        return artwork
    }
}
