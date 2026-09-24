import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        let rect = NSRect(x: 28, y: 28, width: 456, height: 456)
        let rounded = NSBezierPath(roundedRect: rect, xRadius: 110, yRadius: 110)
        NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.23, blue: 0.21, alpha: 1),
                   ending: NSColor(srgbRed: 0.055, green: 0.075, blue: 0.09, alpha: 1))!.draw(in: rounded, angle: -65)
        NSColor(srgbRed: 0.47, green: 0.94, blue: 0.72, alpha: 1).setFill()
        let heights: [CGFloat] = [65, 128, 198, 104, 155]
        for (index, height) in heights.enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 135 + CGFloat(index) * 49, y: 270 - height / 2,
                                            width: 27, height: height), xRadius: 13.5, yRadius: 13.5).fill()
        }
        NSColor.white.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: NSRect(x: 158, y: 111, width: 196, height: 10), xRadius: 5, yRadius: 5).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
