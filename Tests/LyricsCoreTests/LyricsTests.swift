import XCTest
@testable import LyricsCore

final class LyricsTests: XCTestCase {
    func testMultipleTimestampsFractionPrecisionAndSorting() {
        let result = LRCParser.parse("""
        [ar:Example]
        [00:20.125][00:40.50]Refrão
        [00:02.5]Começo
        [01:01]Final
        invalid text
        """)
        XCTAssertEqual(result.map(\.time), [2.5, 20.125, 40.5, 61])
        XCTAssertEqual(result.map(\.text), ["Começo", "Refrão", "Refrão", "Final"])
        XCTAssertEqual(result.map(\.id), [0, 1, 2, 3])
    }

    func testOffsetAppliesToEntireFileAndPreservesNegativeStart() {
        let lyrics = Lyrics(synced: "[00:00.00]Antes\n[00:02.00]Depois\n[offset:+500]", plain: nil)
        XCTAssertEqual(lyrics.lines.map(\.time), [-0.5, 1.5])
        XCTAssertEqual(lyrics.activeLine(at: 0)?.text, "Antes")
        XCTAssertEqual(LRCParser.parse("[offset:-250]\n[00:01.00]A").first?.time, 1.25)
    }

    func testSeekBoundariesIntroAndInstrumentalGaps() {
        let lyrics = Lyrics(synced: "[00:05]Primeira\n[00:10]Segunda\n[00:15]\n[00:20]Última", plain: nil)
        XCTAssertNil(lyrics.activeLine(at: 4.99))
        XCTAssertEqual(lyrics.activeLine(at: 10)?.text, "Segunda")
        XCTAssertEqual(lyrics.activeLine(at: 17)?.text, "")
        XCTAssertEqual(lyrics.activeLine(at: 20)?.text, "Última")
        XCTAssertEqual(lyrics.activeLine(at: 6)?.text, "Primeira")
        XCTAssertNil(lyrics.activeLine(at: .nan))
    }

    func testSimultaneousLinesDoNotLoseText() {
        let lyrics = Lyrics(synced: "[00:02]Original\n[00:02]Tradução\n[00:02]", plain: nil)
        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertEqual(lyrics.activeLine(at: 2)?.text, "Original / Tradução")
    }

    func testPlainLyricsInstrumentalAndEmptyResults() {
        XCTAssertEqual(Lyrics(synced: nil, plain: "  Palavras\n ").plainText, "Palavras")
        XCTAssertTrue(Lyrics(synced: nil, plain: nil, instrumental: true).isAvailable)
        XCTAssertFalse(Lyrics(synced: "[ar:Someone]", plain: nil).isAvailable)
        XCTAssertTrue(Lyrics(synced: "[00:01]Olá", plain: nil).isAvailable)
    }

    func testPlaybackInterpolationPauseAndDurationClamp() {
        let track = Track(id: "1", title: "Song", artist: "Artist", album: "Album", duration: 100)
        let playing = PlaybackSnapshot(track: track, isPlaying: true, position: 30, sampledAt: 1000)
        XCTAssertEqual(playing.position(at: 1002.5), 32.5)
        XCTAssertEqual(playing.position(at: 2000), 100)
        XCTAssertEqual(playing.position(at: 999), 30)
        let paused = PlaybackSnapshot(track: track, isPlaying: false, position: 30, sampledAt: 1000)
        XCTAssertEqual(paused.position(at: 1010), 30)
    }

    func testRequestEncodesMetadataAndDuration() throws {
        let track = Track(id: "1", title: "Olá & você?", artist: "A + B", album: "Álbum / Deluxe", duration: 180.6)
        let request = LyricsClient.request(for: track)
        let url = try XCTUnwrap(request.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "lrclib.net")
        XCTAssertFalse(URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedQuery!.contains("+"))
        XCTAssertEqual(query.first { $0.name == "track_name" }?.value, track.title)
        XCTAssertEqual(query.first { $0.name == "artist_name" }?.value, track.artist)
        XCTAssertEqual(query.first { $0.name == "duration" }?.value, "181")
    }
}

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = ""
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class LyricsClientTests: XCTestCase {
    private let track = Track(id: "1", title: "Title", artist: "Artist", album: "Album", duration: 180)

    private func client(status: Int = 200, body: String = "") -> LyricsClient {
        StubProtocol.status = status
        StubProtocol.body = body
        StubProtocol.requests = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return LyricsClient(session: URLSession(configuration: configuration))
    }

    func testSuccessfulLyricsAreCachedAndRefreshBypassesCache() async throws {
        let service = client(body: #"{"instrumental":false,"plainLyrics":"Olá","syncedLyrics":"[00:01.00]Olá"}"#)
        let first = try await service.fetch(for: track)
        let cached = try await service.fetch(for: track)
        XCTAssertEqual(first?.lines.first?.text, "Olá")
        XCTAssertEqual(first, cached)
        XCTAssertEqual(StubProtocol.requests, 1)
        _ = try await service.fetch(for: track, force: true)
        XCTAssertEqual(StubProtocol.requests, 2)
    }

    func testSearchFiltersEmptyAndRanksSyncedByDuration() async throws {
        let body = #"[{"id":1,"trackName":"T","artistName":"A","albumName":"B","duration":180,"instrumental":false,"plainLyrics":"plain"},{"id":2,"trackName":"T","artistName":"A","albumName":"B","duration":200,"instrumental":false,"syncedLyrics":"[00:01]far"},{"id":3,"trackName":"T","artistName":"A","albumName":"B","duration":181,"instrumental":false,"syncedLyrics":"[00:01]near"},{"id":4,"trackName":"T","artistName":"A","albumName":"B","duration":180,"instrumental":false}]"#
        let results = try await client(body: body).search(for: track)
        XCTAssertEqual(results.map(\.id), [3, 2, 1])
    }

    func testNotFoundReturnsNil() async throws {
        let result = try await client(status: 404).fetch(for: track)
        XCTAssertNil(result)
    }

    func testRateLimitIsAnErrorNotMissingLyrics() async throws {
        do {
            _ = try await client(status: 429).fetch(for: track)
            XCTFail("Expected rate limit error")
        } catch LyricsServiceError.http(let code) { XCTAssertEqual(code, 429) }
    }

    func testMalformedResponseThrows() async throws {
        do {
            _ = try await client(body: "not json").fetch(for: track)
            XCTFail("Expected decoding error")
        } catch is DecodingError { }
    }

    func testInstrumentalIsAvailableWithoutText() async throws {
        let result = try await client(body: #"{"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#).fetch(for: track)
        XCTAssertTrue(result?.instrumental == true)
    }

    func testEmptyRecordIsUnavailable() async throws {
        let result = try await client(body: #"{"instrumental":false,"plainLyrics":null,"syncedLyrics":null}"#).fetch(for: track)
        XCTAssertNil(result)
    }
}
