import XCTest
import SwiftUI
import LyricsCore
@testable import SpotifyLyricsBar

final class PlayerModelTests: XCTestCase {
    @MainActor
    func testFavoritesVersionAndIntensitySurviveRestart() throws {
        let suite = "LyriczFeaturesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PlayerModel(demo: true, defaults: defaults)
        first.start(); defer { first.stop() }
        first.favorite("Um trecho original")
        first.colorIntensity = 0.4
        let version = try JSONDecoder().decode(LyricsVersion.self, from: Data(#"{"id":42,"trackName":"Entre luzes","artistName":"Demo","albumName":"Alternativa","duration":208,"instrumental":false,"syncedLyrics":"[00:00]Outra versão","plainLyrics":null}"#.utf8))
        first.lyricOffset = 2
        first.selectVersion(version)
        XCTAssertEqual(first.lyricOffset, 0)
        XCTAssertEqual(first.barTitle, "Outra versão")
        let reopened = PlayerModel(demo: true, defaults: defaults)
        reopened.start(); defer { reopened.stop() }
        XCTAssertEqual(reopened.selectedVersionID, 42)
        XCTAssertEqual(reopened.barTitle, "Outra versão")
        XCTAssertEqual(reopened.colorIntensity, 0.4)
        XCTAssertEqual(reopened.favorites.first?.title, "Entre luzes")
        XCTAssertTrue(reopened.isFavorite("Um trecho original"))
        reopened.favorite("Um trecho original")
        XCTAssertTrue(reopened.favorites.isEmpty)
        XCTAssertTrue(PlayerModel(demo: true, defaults: defaults).favorites.isEmpty)
    }

    @MainActor
    func testShareCardRendersCompleteLongExcerpt() throws {
        let excerpt = FavoriteExcerpt(trackID: "test", title: "Uma música", artist: "Um artista",
                                      text: String(repeating: "Um verso para lembrar. ", count: 20), artwork: nil)
        let renderer = ImageRenderer(content: ExcerptCard(excerpt: excerpt))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 540)
        XCTAssertGreaterThan(image.height, 700, "Long excerpts must grow instead of clipping")
    }

    @MainActor
    func testClickingLyricsChangesPositionAndRespectsCompactionPreference() async throws {
        let suite = "LyricsBarModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlayerModel(demo: true, defaults: defaults)
        model.start()
        defer { model.stop() }
        model.control(.playPause)
        let lines = try XCTUnwrap(model.lyrics?.lines)
        model.seek(to: lines[0])
        XCTAssertEqual(model.barTitle, "Entre luzes · Sessão de demonstração")
        XCTAssertEqual(model.statusBarWidth, model.barWidth)
        model.seek(to: lines.first { $0.time == 88 }!)
        XCTAssertEqual(model.position, 88, accuracy: 0.01)
        XCTAssertEqual(model.barTitle, "♪")
        XCTAssertEqual(model.statusBarWidth, 28)
        model.compactInstrumentals = false
        XCTAssertEqual(model.statusBarWidth, model.barWidth)
        model.compactInstrumentals = true
        XCTAssertFalse(model.isPlaying, "Seeking must preserve pause state")
        model.seek(to: lines[1])
        XCTAssertEqual(model.barTitle, lines[1].text)
        XCTAssertEqual(model.statusBarWidth, model.barWidth)
        model.seek(to: lines[0])
        XCTAssertTrue(model.barTitle.contains("Entre luzes"))
        model.showLyricsInBar = false
        XCTAssertEqual(model.statusBarWidth, 28)
    }

    @MainActor
    func testCorrectionRestoresAfterAppReopensAndAffectsSeek() async throws {
        let suite = "LyricsBarModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PlayerModel(demo: true, defaults: defaults)
        XCTAssertEqual(first.scrollSpeed, 25)
        XCTAssertTrue(first.useAlbumColors)
        first.start()
        first.lyricOffset = 2.5
        first.scrollSpeed = 36
        first.useAlbumColors = false
        first.stop()
        let reopened = PlayerModel(demo: true, defaults: defaults)
        reopened.start()
        defer { reopened.stop() }
        XCTAssertEqual(reopened.lyricOffset, 2.5)
        XCTAssertEqual(reopened.scrollSpeed, 36)
        XCTAssertFalse(reopened.useAlbumColors)
        reopened.control(.playPause)
        let line = try XCTUnwrap(reopened.lyrics?.lines.first { $0.time == 50 })
        reopened.seek(to: line)
        XCTAssertEqual(reopened.position, 47.5, accuracy: 0.01)
        XCTAssertEqual(reopened.activeLineID, line.id)
        reopened.lyricOffset = 0
        XCTAssertEqual(TrackOffsetStore(defaults: defaults).offset(for: "demo"), 0)
    }
}
