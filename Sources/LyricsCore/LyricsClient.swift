import Foundation

public enum LyricsServiceError: LocalizedError {
    case invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "O serviço de letras enviou uma resposta inválida."
        case .http(429): return "O serviço de letras está ocupado. Tente novamente em instantes."
        case .http(let code): return "Não foi possível consultar as letras (HTTP \(code))."
        }
    }
}

public actor LyricsClient {
    private let session: URLSession
    private var cache: [TrackKey: Lyrics] = [:]
    private var cacheOrder: [TrackKey] = []

    private struct TrackKey: Hashable {
        let title: String
        let artist: String
        let album: String
        let duration: Int
        init(_ track: Track) {
            title = track.title; artist = track.artist; album = track.album
            duration = Int(track.duration.rounded())
        }
    }

    public init(session: URLSession = .shared) { self.session = session }

    public static func request(for track: Track) -> URLRequest {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
        ]
        // The server decodes form-style queries, where an unescaped + means a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Lyricz/1.3 (macOS; personal lyrics viewer)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func fetch(for track: Track, force: Bool = false) async throws -> Lyrics? {
        let key = TrackKey(track)
        if !force, let existing = cache[key] { return existing }
        let (data, response) = try await session.data(for: Self.request(for: track))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LyricsServiceError.invalidResponse }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw LyricsServiceError.http(response.statusCode) }
        let record = try JSONDecoder().decode(Record.self, from: data)
        let lyrics = Lyrics(synced: record.syncedLyrics, plain: record.plainLyrics, instrumental: record.instrumental)
        guard lyrics.isAvailable else { return nil }
        cache[key] = lyrics
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        if cacheOrder.count > 60 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        return lyrics
    }

    public func search(for track: Track) async throws -> [LyricsVersion] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                                 URLQueryItem(name: "artist_name", value: track.artist)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Lyricz/1.4 (macOS; personal lyrics viewer)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LyricsServiceError.invalidResponse }
        guard response.statusCode == 200 else { throw LyricsServiceError.http(response.statusCode) }
        return try JSONDecoder().decode([LyricsVersion].self, from: data)
            .filter { $0.lyrics.isAvailable }
            .sorted {
                if $0.lyrics.lines.isEmpty != $1.lyrics.lines.isEmpty { return !$0.lyrics.lines.isEmpty }
                let a = abs($0.duration - track.duration), b = abs($1.duration - track.duration)
                return a == b ? $0.id < $1.id : a < b
            }
    }

    private struct Record: Decodable {
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?
    }
}
