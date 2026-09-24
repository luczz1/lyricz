import AppKit
import LyricsCore

/// A non-interactive overlay: NSStatusBarButton keeps click, highlight, tooltip and accessibility.
@MainActor
final class MarqueeTextView: NSView {
    private var text = ""
    private let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private var textWidth: CGFloat = 0
    private var elapsed: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var timer: Timer?
    private var scrollingEnabled = false
    private var lastWidth: CGFloat = 0
    private var showText = true
    private var symbol = "waveform"
    private var speed = MarqueeMotion.defaultSpeed

    var iconFrame: NSRect { NSRect(x: 6, y: (bounds.height - 16) / 2, width: 16, height: 16) }
    var textFrame: NSRect { NSRect(x: 30, y: 0, width: max(0, bounds.width - 38), height: bounds.height) }

    private var hasReachedEnd: Bool {
        let overflow = max(0, textWidth - textFrame.width)
        return MarqueeMotion.offset(elapsed: elapsed, textWidth: textWidth, viewportWidth: textFrame.width, speed: speed) >= overflow
    }

    override var allowsVibrancy: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(text: String, running: Bool, scroll: Bool, showText: Bool = true,
                   symbol: String = "waveform", speed requestedSpeed: Double = MarqueeMotion.defaultSpeed) {
        if self.text != text || bounds.width != lastWidth {
            self.text = text
            lastWidth = bounds.width
            textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            elapsed = 0
            lastTick = ProcessInfo.processInfo.systemUptime
        }
        let newSpeed = MarqueeMotion.clampedSpeed(requestedSpeed)
        if speed != newSpeed {
            // Preserve the visible position when adjusting speed, including when already at the end.
            if elapsed > MarqueeMotion.startPause {
                let position = MarqueeMotion.offset(elapsed: elapsed, textWidth: textWidth,
                                                    viewportWidth: textFrame.width, speed: speed)
                elapsed = MarqueeMotion.startPause + position / newSpeed
            }
            speed = newSpeed
        }
        self.showText = showText
        self.symbol = symbol
        scrollingEnabled = scroll && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = scrollingEnabled && running && showText && !isHidden
            && textFrame.width > 0 && !hasReachedEnd
        if shouldAnimate && timer == nil {
            lastTick = ProcessInfo.processInfo.systemUptime
            let ticker = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    // The timer is installed exclusively on the main run loop.
                    // Avoid leaping forward after system sleep or a suspended run loop.
                    self.elapsed += min(0.1, max(0, now - self.lastTick))
                    self.lastTick = now
                    self.needsDisplay = true
                    if self.hasReachedEnd { self.stopAnimation() }
                }
            }
            ticker.tolerance = 0.005
            RunLoop.main.add(ticker, forMode: .common)
            timer = ticker
        } else if !shouldAnimate {
            stopAnimation()
        }
        needsDisplay = true
    }

    func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        let highlighted = (superview as? NSStatusBarButton)?.isHighlighted ?? false
        let color = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [color]))
        icon?.draw(in: iconFrame)

        guard showText, !text.isEmpty, textFrame.width > 0 else { return }
        // Keep the single moving phrase inside its own area, clear of the fixed icon.
        textFrame.clip()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let height = (text as NSString).size(withAttributes: attributes).height
        let y = (bounds.height - height) / 2
        if scrollingEnabled && textWidth > textFrame.width {
            let offset = MarqueeMotion.offset(elapsed: elapsed, textWidth: textWidth, viewportWidth: textFrame.width, speed: speed)
            (text as NSString).draw(at: NSPoint(x: textFrame.minX - offset, y: y), withAttributes: attributes)
        } else {
            var staticAttributes = attributes
            staticAttributes[.paragraphStyle] = paragraph
            (text as NSString).draw(in: NSRect(x: textFrame.minX, y: y, width: textFrame.width, height: height), withAttributes: staticAttributes)
        }
    }
}
