import Foundation

public struct PaletteColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    public func mixed(with other: PaletteColor, amount: Double) -> PaletteColor {
        PaletteColor(red + (other.red - red) * amount, green + (other.green - green) * amount,
                 blue + (other.blue - blue) * amount)
    }

    public var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public func contrast(with other: PaletteColor) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

public struct AlbumPalette: Equatable, Sendable {
    public let top: PaletteColor
    public let bottom: PaletteColor
    public let accent: PaletteColor

    public static let fallback = AlbumPalette(top: PaletteColor(0.075, 0.09, 0.10),
                                             bottom: PaletteColor(0.055, 0.065, 0.075),
                                             accent: PaletteColor(0.47, 0.94, 0.72))

    public func intensity(_ value: Double) -> AlbumPalette {
        let amount = min(1, max(0, value.isFinite ? value : 1))
        return AlbumPalette(top: Self.fallback.top.mixed(with: top, amount: amount),
                            bottom: Self.fallback.bottom.mixed(with: bottom, amount: amount),
                            accent: Self.fallback.accent.mixed(with: accent, amount: amount))
    }

    /// Input is a small sRGB bitmap in premultiplied RGBA byte order.
    public static func extract(rgba: [UInt8]) -> AlbumPalette {
        struct Bucket {
            var count = 0.0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var color: PaletteColor { PaletteColor(red / count, green / count, blue / count) }
            var score: Double {
                let c = color
                let high = max(c.red, c.green, c.blue)
                let saturation = high > 0 ? (high - min(c.red, c.green, c.blue)) / high : 0
                return count * (0.85 + 0.15 * saturation)
            }
        }
        var buckets: [Int: Bucket] = [:]
        var all = Bucket()
        for index in stride(from: 0, to: rgba.count - rgba.count % 4, by: 4) {
            let alpha = Double(rgba[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let color = PaletteColor(Double(rgba[index]) / 255 / alpha,
                                 Double(rgba[index + 1]) / 255 / alpha,
                                 Double(rgba[index + 2]) / 255 / alpha)
            all.count += 1; all.red += color.red; all.green += color.green; all.blue += color.blue
            let high = max(color.red, color.green, color.blue)
            let low = min(color.red, color.green, color.blue)
            // Avoid black margins and white lettering overpowering the actual cover colors.
            guard high > 0.12, low < 0.92 else { continue }
            // Group nearby shades by hue: RGB cubes split a pastel background
            // into many small groups and let a tiny saturated detail win.
            let delta = high - low
            let saturation = delta / high
            let key: Int
            if saturation < 0.18 {
                key = 12 + Int(high * 4)
            } else {
                var hue: Double
                if high == color.red { hue = (color.green - color.blue) / delta }
                else if high == color.green { hue = 2 + (color.blue - color.red) / delta }
                else { hue = 4 + (color.red - color.green) / delta }
                if hue < 0 { hue += 6 }
                key = Int((hue * 2 + 0.5).rounded(.down)) % 12
            }
            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1; bucket.red += color.red; bucket.green += color.green; bucket.blue += color.blue
            buckets[key] = bucket
        }
        guard all.count > 0 else { return .fallback }
        let ranked = buckets.sorted {
            $0.value.score == $1.value.score ? $0.key < $1.key : $0.value.score > $1.value.score
        }
        // Prefer a substantial colorful detail over a beige/gray background, while
        // still allowing genuinely monochrome artwork to produce a neutral theme.
        let colorful = ranked.first { entry in
            let c = entry.value.color
            let high = max(c.red, c.green, c.blue)
            let saturation = high > 0 ? (high - min(c.red, c.green, c.blue)) / high : 0
            return saturation >= 0.18 && entry.value.count >= max(2, all.count * 0.02)
        }
        let primary = colorful?.value.color ?? ranked.first?.value.color ?? all.color
        let secondary = ranked.first { entry in
            let c = entry.value.color
            let distance = abs(c.red - primary.red) + abs(c.green - primary.green) + abs(c.blue - primary.blue)
            return entry.key < 12 && distance > 0.35 && entry.value.count >= all.count * 0.04
        }?.value.color ?? primary
        let black = PaletteColor(0.025, 0.03, 0.04)
        var top = primary.mixed(with: black, amount: 0.60)
        while PaletteColor(1, 1, 1).contrast(with: top) < 7 {
            top = top.mixed(with: black, amount: 0.1)
        }
        let bottom = secondary.mixed(with: black, amount: 0.78)
        var accent = primary.mixed(with: PaletteColor(1, 1, 1), amount: 0.42)
        // The active lyric and control labels must remain readable on every cover.
        while min(accent.contrast(with: top), accent.contrast(with: bottom)) < 7 {
            accent = accent.mixed(with: PaletteColor(1, 1, 1), amount: 0.1)
        }
        return AlbumPalette(top: top, bottom: bottom, accent: accent)
    }
}
