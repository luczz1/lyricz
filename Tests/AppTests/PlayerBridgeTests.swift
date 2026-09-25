import AppKit
import XCTest
import LyricsCore
@testable import SpotifyLyricsBar

final class PlayerBridgeTests: XCTestCase {
    func testMusicAndSpotifyUseDifferentDurationUnitsAndTrackNamespaces() throws {
        func descriptor(id: String, duration: Double) -> NSAppleEventDescriptor {
            let list = NSAppleEventDescriptor.list()
            let values = [NSAppleEventDescriptor(string: id), .init(string: "Track"), .init(string: "Artist"),
                          .init(string: "Album"), .init(double: duration), .init(string: ""), .init(double: 15), .init(boolean: true)]
            for (index, value) in values.enumerated() { list.insert(value, at: index + 1) }
            return list
        }
        let music = try XCTUnwrap(PlayerBridge(source: .appleMusic).decodeSnapshot(descriptor(id: "AB1234", duration: 180)))
        let spotify = try XCTUnwrap(PlayerBridge(source: .spotify).decodeSnapshot(descriptor(id: "spotify:track:1234", duration: 180000)))
        XCTAssertEqual(music.track.id, "appleMusic:AB1234")
        XCTAssertEqual(spotify.track.id, "spotify:track:1234")
        XCTAssertEqual(music.track.duration, spotify.track.duration)
        XCTAssertEqual(music.position(at: music.sampledAt), 15)
        XCTAssertTrue(music.isPlaying)
        XCTAssertNil(PlayerBridge(source: .spotify).decodeSnapshot(descriptor(id: "spotify:episode:1234", duration: 180000)))
    }

    func testMusicScriptCompilesAgainstInstalledDictionary() throws {
        let script = try XCTUnwrap(NSAppleScript(source: PlayerBridge.musicSnapshotScript))
        var error: NSDictionary?
        XCTAssertTrue(script.compileAndReturnError(&error), "\(String(describing: error))")
    }

    @MainActor func testManualPlayerChoicePersists() {
        let suite = "LyriczPlayers.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerModel(demo: true, defaults: defaults)
        XCTAssertEqual(model.playerPreference, .automatic)
        model.playerPreference = .appleMusic
        XCTAssertEqual(PlayerModel(demo: true, defaults: defaults).playerPreference, .appleMusic)
        model.playerPreference = .automatic
        XCTAssertEqual(PlayerModel(demo: true, defaults: defaults).playerPreference, .automatic)
    }
}
