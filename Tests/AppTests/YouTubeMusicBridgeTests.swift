import AppKit
import JavaScriptCore
import XCTest
import LyricsCore
@testable import SpotifyLyricsBar

final class YouTubeMusicBridgeTests: XCTestCase {
    func testMetadataAndPlaybackAreDecodedWithStableYouTubeIdentity() throws {
        let snapshot = try XCTUnwrap(YouTubeMusicBridge.decode("""
        {"id":"abc_123-xyz","title":"All We Know","artist":"Paramore","album":"All We Know Is Falling",
        "duration":193.5,"position":25.2,"playing":true,"artwork":"https://i.ytimg.com/vi/abc/default.jpg"}
        """))
        XCTAssertEqual(snapshot.track.id, "youtubeMusic:abc_123-xyz")
        XCTAssertEqual(snapshot.track.artist, "Paramore")
        XCTAssertEqual(snapshot.track.duration, 193.5)
        XCTAssertEqual(snapshot.position(at: snapshot.sampledAt), 25.2)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertNotNil(snapshot.track.artworkURL)
        XCTAssertNil(try YouTubeMusicBridge.decode("null"))
        XCTAssertNil(try YouTubeMusicBridge.decode("""
        {"id":"123","title":"Live","artist":"Artist","album":"","duration":0,"position":0,"playing":true}
        """))
    }

    func testBrowserScriptsCompileAgainstInstalledDictionaries() throws {
        for browser in YouTubeMusicBridge.browsers where NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) != nil {
            let script = try XCTUnwrap(NSAppleScript(source: YouTubeMusicBridge.discoveryScript(browser)))
            var error: NSDictionary?
            XCTAssertTrue(script.compileAndReturnError(&error), "\(browser.name): \(String(describing: error))")
        }
    }

    func testPageReaderRejectsOtherOriginsAndAdsAndReadsPausedTracks() throws {
        let js = try XCTUnwrap(JSContext())
        js.evaluateScript("""
        var location = { origin: 'https://music.youtube.com', href: 'https://music.youtube.com/watch?v=abc' };
        var ad = false;
        var video = { duration: 180, currentTime: 40, paused: true, ended: false };
        var navigator = { mediaSession: { metadata: { title: 'Song', artist: 'Artist', album: 'Album', artwork: [{src:'https://i.ytimg.com/art.jpg'}] } } };
        var player = { getVideoData: () => ({ video_id: 'abc' }), classList: { contains: () => ad } };
        var document = { querySelector: (q) => q === 'video' ? video : q === '#movie_player' ? player : null };
        """)
        let json = try XCTUnwrap(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString())
        XCTAssertNil(js.exception)
        let snapshot = try XCTUnwrap(YouTubeMusicBridge.decode(json))
        XCTAssertEqual(snapshot.track.title, "Song")
        XCTAssertFalse(snapshot.isPlaying)
        // The current miniplayer exposes the video ID on its title link rather
        // than a page-world getVideoData method (including on playlist URLs).
        js.evaluateScript("player.getVideoData = undefined; player.querySelector = () => ({href:'https://music.youtube.com/watch?v=new_ID-123'});")
        let currentLayout = try XCTUnwrap(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString())
        XCTAssertNil(js.exception)
        XCTAssertEqual(try YouTubeMusicBridge.decode(currentLayout)?.track.id, "youtubeMusic:new_ID-123")
        js.evaluateScript("ad = true")
        XCTAssertEqual(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString(), "null")
        js.evaluateScript("ad = false; location.origin = 'https://music.youtube.com.evil.example'")
        XCTAssertEqual(js.evaluateScript(YouTubeMusicBridge.snapshotJavaScript)?.toString(), "null")
    }

    func testYouTubeParticipatesInAutomaticSelectionAndManualPreferencePersists() async {
        let track = Track(id: "youtubeMusic:abc", title: "Song", artist: "Artist", album: "", duration: 100)
        let reading = PlaybackSnapshot(track: track, isPlaying: true, position: 0)
        XCTAssertEqual(PlayerSelection.choose(readings: [.youtubeMusic: reading], current: .spotify,
                                              previouslyPlaying: []), .youtubeMusic)
        await MainActor.run {
            let name = "LyriczYouTubeTests.\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let model = PlayerModel(demo: true, defaults: defaults)
            model.playerPreference = .youtubeMusic
            XCTAssertEqual(PlayerModel(demo: true, defaults: defaults).playerPreference, .youtubeMusic)
        }
    }
}
