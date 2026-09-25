import AppKit
import XCTest
@testable import SpotifyLyricsBar

final class MoreOptionsMenuTests: XCTestCase {
    @MainActor func testPlayerSubmenuIsStableAndActionsSelectCorrectPlayer() throws {
        let suite = "LyriczMenuTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerModel(demo: true, defaults: defaults)
        model.start(); defer { model.stop() }
        let view = MoreOptionsMenu(model: model, showFavorites: {}, showVersions: {})
        let coordinator = view.makeCoordinator()
        let menu = coordinator.buildMenu()
        let players = try XCTUnwrap(menu.item(withTitle: "Player")?.submenu)
        XCTAssertEqual(players.items.map(\.title), ["Automático", "Spotify", "Apple Music"])
        XCTAssertEqual(players.items[0].state, .on)
        model.control(.playPause)
        model.colorIntensity = 0.3
        coordinator.parent = MoreOptionsMenu(model: model, showFavorites: {}, showVersions: {})
        XCTAssertTrue(menu.item(withTitle: "Player")?.submenu === players)
        coordinator.performAction(players.items[2])
        XCTAssertEqual(model.playerPreference, .appleMusic)
        let reopened = try XCTUnwrap(coordinator.buildMenu().item(withTitle: "Player")?.submenu)
        XCTAssertEqual(reopened.items[2].state, .on)
        XCTAssertEqual(reopened.items[0].state, .off)
    }
}
