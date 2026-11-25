import Foundation

public enum PlayerSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case spotify, appleMusic, youtubeMusic
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .youtubeMusic: return "YouTube Music"
        }
    }
    public var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        case .youtubeMusic: return "com.google.Chrome"
        }
    }
}

public enum PlayerPreference: String, CaseIterable, Identifiable {
    case automatic, spotify, appleMusic, youtubeMusic
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
