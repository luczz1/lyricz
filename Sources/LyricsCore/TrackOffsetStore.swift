import Foundation

/// Stores only nonzero corrections, keyed by Spotify URI rather than title or artist.
public final class TrackOffsetStore {
    private let defaults: UserDefaults
    private let key = "lyricOffsetsByTrack"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func offset(for trackID: String) -> Double {
        let value = (defaults.dictionary(forKey: key)?[trackID] as? NSNumber)?.doubleValue ?? 0
        return value.isFinite ? min(5, max(-5, value)) : 0
    }

    public func save(_ offset: Double, for trackID: String) {
        guard !trackID.isEmpty, offset.isFinite else { return }
        var values = defaults.dictionary(forKey: key) ?? [:]
        let bounded = min(5, max(-5, offset))
        if bounded == 0 { values.removeValue(forKey: trackID) }
        else { values[trackID] = bounded }
        defaults.set(values, forKey: key)
    }
}
