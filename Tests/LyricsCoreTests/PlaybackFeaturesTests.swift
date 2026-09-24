import XCTest
@testable import LyricsCore

final class PlaybackFeaturesTests: XCTestCase {
    func testIntroWordsInstrumentalAndSeekBack() {
        let lyrics = Lyrics(synced: "[00:00]\n[00:08]Começo\n[00:20]\n[00:25]Refrão\n[00:35]♪ ♪ ♪", plain: nil)
        XCTAssertEqual(lyrics.moment(at: 0), .intro)
        XCTAssertEqual(lyrics.moment(at: 7.99), .intro)
        XCTAssertEqual(lyrics.moment(at: 8), .words("Começo"))
        XCTAssertEqual(lyrics.moment(at: 20), .instrumental)
        XCTAssertEqual(lyrics.moment(at: 26), .words("Refrão"))
        XCTAssertEqual(lyrics.moment(at: 35), .instrumental)
        XCTAssertEqual(lyrics.moment(at: 3), .intro)
        XCTAssertEqual(Lyrics(synced: nil, plain: "Letra").moment(at: 20), .unavailable)
        XCTAssertEqual(Lyrics(synced: nil, plain: nil, instrumental: true).moment(at: 20), .instrumental)
    }

    func testSeekUsesBothLRCAndUserOffsetsAndClampsToTrack() {
        let lines = LRCParser.parse("[offset:500]\n[00:01]Começo\n[00:30]Fim")
        XCTAssertEqual(lines[1].playbackPosition(offset: 2.5, duration: 100), 27)
        XCTAssertEqual(lines[1].playbackPosition(offset: -2.5, duration: 100), 32)
        XCTAssertEqual(lines[0].playbackPosition(offset: 2.5, duration: 100), 0)
        XCTAssertEqual(lines[1].playbackPosition(offset: -2.5, duration: 30), 30)
    }

    func testCorrectionsSurviveNewStoreAndStaySeparateByTrack() {
        let suite = "LyricsBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrackOffsetStore(defaults: defaults)
        store.save(1.25, for: "spotify:track:first")
        store.save(-0.75, for: "spotify:track:second")
        let reopened = TrackOffsetStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reopened.offset(for: "spotify:track:first"), 1.25)
        XCTAssertEqual(reopened.offset(for: "spotify:track:second"), -0.75)
        XCTAssertEqual(reopened.offset(for: "spotify:track:unknown"), 0)
        reopened.save(0, for: "spotify:track:first")
        XCTAssertEqual(store.offset(for: "spotify:track:first"), 0)
        XCTAssertEqual(store.offset(for: "spotify:track:second"), -0.75)
    }

    func testMarqueeMovesSlowlyThenStaysAtTheEnd() {
        let width = 300.0
        let viewport = 160.0
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 1, textWidth: width, viewportWidth: viewport), 0)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 2.2, textWidth: width, viewportWidth: viewport), 25, accuracy: 0.0001)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 6.2, textWidth: width, viewportWidth: viewport), 125, accuracy: 0.0001)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 8, textWidth: width, viewportWidth: viewport), 140)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 60, textWidth: width, viewportWidth: viewport), 140)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 3600, textWidth: width, viewportWidth: viewport), 140)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 2.2, textWidth: width, viewportWidth: viewport, speed: 50), 50, accuracy: 0.0001)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 60, textWidth: width, viewportWidth: viewport, speed: 10), 140)
        var previous = 0.0
        for elapsed in stride(from: 0.0, through: 30.0, by: 0.1) {
            let offset = MarqueeMotion.offset(elapsed: elapsed, textWidth: width, viewportWidth: viewport)
            XCTAssertGreaterThanOrEqual(offset, previous)
            XCTAssertLessThanOrEqual(offset, width - viewport)
            previous = offset
        }
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 5, textWidth: 100, viewportWidth: viewport), 0)
        XCTAssertEqual(MarqueeMotion.offset(elapsed: 5, textWidth: width, viewportWidth: 0), 0)
    }
}
