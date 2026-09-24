import Foundation

public struct LyricsVersion: Codable, Identifiable, Sendable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let albumName: String
    public let duration: Double
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?
    public var lyrics: Lyrics { Lyrics(synced: syncedLyrics, plain: plainLyrics, instrumental: instrumental) }
}

public struct FavoriteExcerpt: Codable, Identifiable, Equatable {
    public var id = UUID()
    public let trackID: String
    public let title: String
    public let artist: String
    public let text: String
    public let artwork: Data?
    public init(trackID: String, title: String, artist: String, text: String, artwork: Data?) {
        self.trackID = trackID; self.title = title; self.artist = artist; self.text = text; self.artwork = artwork
    }
}
