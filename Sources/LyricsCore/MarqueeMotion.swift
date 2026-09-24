import Foundation

/// Pauses briefly, reveals the end of the phrase once, and stays there.
public enum MarqueeMotion {
    public static let defaultSpeed: Double = 25
    public static let speedRange: ClosedRange<Double> = 10...60
    public static let startPause: Double = 1.2

    public static func clampedSpeed(_ value: Double) -> Double {
        value.isFinite ? min(speedRange.upperBound, max(speedRange.lowerBound, value)) : defaultSpeed
    }

    public static func offset(elapsed: Double, textWidth: Double, viewportWidth: Double,
                              speed: Double = defaultSpeed) -> Double {
        guard elapsed.isFinite, textWidth.isFinite, viewportWidth.isFinite,
              speed.isFinite, speed > 0, viewportWidth > 0, textWidth > viewportWidth else { return 0 }
        let overflow = textWidth - viewportWidth
        return min(overflow, max(0, elapsed - startPause) * speed)
    }
}
