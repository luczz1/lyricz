import Foundation

public enum PlayerSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case spotify, appleMusic
    public var id: String { rawValue }
    public var name: String { self == .spotify ? "Spotify" : "Apple Music" }
    public var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

public enum PlayerPreference: String, CaseIterable, Identifiable {
    case automatic, spotify, appleMusic
    public var id: String { rawValue }
    public var source: PlayerSource? { PlayerSource(rawValue: rawValue) }
    public var name: String { source?.name ?? "Automático" }
}

public enum PlayerSelection {
    /// A newly started player wins. Otherwise keep the current player to avoid oscillation.
    public static func choose(readings: [PlayerSource: PlaybackSnapshot], current: PlayerSource?,
                              previouslyPlaying: Set<PlayerSource>) -> PlayerSource? {
        let playing = Set(readings.filter { $0.value.isPlaying }.map(\.key))
        let started = playing.subtracting(previouslyPlaying)
        if started.count == 1 { return started.first }
        if let current, playing.contains(current) { return current }
        if let next = PlayerSource.allCases.first(where: { playing.contains($0) }) { return next }
        if let current, readings[current] != nil { return current }
        return PlayerSource.allCases.first { readings[$0] != nil }
    }
}
