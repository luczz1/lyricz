import XCTest
@testable import LyricsCore

final class PlayerSelectionTests: XCTestCase {
    private func reading(_ playing: Bool) -> PlaybackSnapshot {
        PlaybackSnapshot(track: Track(id: "test", title: "T", artist: "A", album: "B", duration: 180), isPlaying: playing, position: 10)
    }

    func testNewlyPlayingPlayerWinsAndStaysStableWhenBothPlay() {
        let both: [PlayerSource: PlaybackSnapshot] = [.spotify: reading(true), .appleMusic: reading(true)]
        XCTAssertEqual(PlayerSelection.choose(readings: both, current: .spotify, previouslyPlaying: [.spotify]), .appleMusic)
        XCTAssertEqual(PlayerSelection.choose(readings: both, current: .appleMusic, previouslyPlaying: [.spotify, .appleMusic]), .appleMusic)
        XCTAssertEqual(PlayerSelection.choose(readings: both, current: .appleMusic, previouslyPlaying: [.appleMusic]), .spotify)
    }

    func testPlayingWinsOverPausedAndClosedPlayerIsDropped() {
        XCTAssertEqual(PlayerSelection.choose(readings: [.spotify: reading(false), .appleMusic: reading(true)], current: .spotify, previouslyPlaying: [.appleMusic]), .appleMusic)
        XCTAssertEqual(PlayerSelection.choose(readings: [.spotify: reading(false)], current: .appleMusic, previouslyPlaying: []), .spotify)
        XCTAssertNil(PlayerSelection.choose(readings: [:], current: .spotify, previouslyPlaying: []))
    }

    func testPausedPlayersKeepSelectionAndColdStartIsDeterministic() {
        let paused: [PlayerSource: PlaybackSnapshot] = [.spotify: reading(false), .appleMusic: reading(false)]
        XCTAssertEqual(PlayerSelection.choose(readings: paused, current: .appleMusic, previouslyPlaying: []), .appleMusic)
        XCTAssertEqual(PlayerSelection.choose(readings: paused, current: nil, previouslyPlaying: []), .spotify)
    }
}
