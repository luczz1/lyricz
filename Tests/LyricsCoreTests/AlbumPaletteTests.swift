import XCTest
@testable import LyricsCore

final class AlbumPaletteTests: XCTestCase {
    private func pixels(_ color: [UInt8], count: Int) -> [UInt8] {
        Array(repeating: color, count: count).flatMap { $0 }
    }

    func testDominantCoverColorsProduceDifferentThemes() {
        let red = AlbumPalette.extract(rgba: pixels([220, 30, 20, 255], count: 80)
            + pixels([10, 50, 200, 255], count: 20))
        let blue = AlbumPalette.extract(rgba: pixels([220, 30, 20, 255], count: 20)
            + pixels([10, 50, 200, 255], count: 80))
        XCTAssertGreaterThan(red.top.red, red.top.blue)
        XCTAssertGreaterThan(blue.top.blue, blue.top.red)
        XCTAssertNotEqual(red, blue)
    }

    func testPastelBackgroundOutweighsSmallSaturatedDetails() {
        // Pink/lilac cover with blue areas and small yellow decorations.
        let palette = AlbumPalette.extract(rgba:
            pixels([210, 155, 205, 255], count: 25)
            + pixels([190, 140, 195, 255], count: 25)
            + pixels([230, 180, 220, 255], count: 20)
            + pixels([35, 180, 220, 255], count: 20)
            + pixels([250, 195, 30, 255], count: 10))
        XCTAssertGreaterThan(palette.top.red, palette.top.green)
        XCTAssertGreaterThan(palette.top.blue, palette.top.green)
        XCTAssertGreaterThan(palette.bottom.blue, palette.bottom.red)
        XCTAssertGreaterThan(palette.accent.blue, palette.accent.green)
    }

    func testIntensityPreservesEndpointsAndReadableText() {
        let palette = AlbumPalette.extract(rgba: pixels([220, 50, 180, 255], count: 100))
        XCTAssertEqual(palette.intensity(0), .fallback)
        XCTAssertEqual(palette.intensity(1).top.red, palette.top.red, accuracy: 0.00001)
        for amount in stride(from: 0.0, through: 1.0, by: 0.1) {
            let adjusted = palette.intensity(amount)
            XCTAssertGreaterThanOrEqual(adjusted.accent.contrast(with: adjusted.top), 7)
            XCTAssertGreaterThanOrEqual(adjusted.accent.contrast(with: adjusted.bottom), 7)
        }
    }

    func testTransparentOrMissingArtworkFallsBack() {
        XCTAssertEqual(AlbumPalette.extract(rgba: []), .fallback)
        XCTAssertEqual(AlbumPalette.extract(rgba: pixels([0, 0, 0, 0], count: 40)), .fallback)
        XCTAssertEqual(AlbumPalette.extract(rgba: [1, 2, 3]), .fallback)
    }

    func testTextContrastRemainsHighAcrossExtremeCovers() {
        let white = PaletteColor(1, 1, 1)
        for color: [UInt8] in [[255, 255, 255, 255], [0, 0, 0, 255], [255, 0, 0, 255],
                              [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255],
                              [120, 120, 120, 255], [60, 10, 40, 128]] {
            let palette = AlbumPalette.extract(rgba: pixels(color, count: 100))
            XCTAssertGreaterThanOrEqual(palette.accent.contrast(with: palette.top), 7)
            XCTAssertGreaterThanOrEqual(palette.accent.contrast(with: palette.bottom), 7)
            XCTAssertGreaterThanOrEqual(white.contrast(with: palette.top), 7)
            XCTAssertGreaterThanOrEqual(white.contrast(with: palette.bottom), 7)
        }
    }

    func testBlackBorderDoesNotHideCoverColor() {
        let palette = AlbumPalette.extract(rgba: pixels([0, 0, 0, 255], count: 90)
            + pixels([20, 180, 60, 255], count: 10))
        XCTAssertGreaterThan(palette.top.green, palette.top.red)
        let beigeCover = AlbumPalette.extract(rgba: pixels([215, 210, 200, 255], count: 90)
            + pixels([230, 140, 20, 255], count: 10))
        XCTAssertGreaterThan(beigeCover.top.red, beigeCover.top.blue * 2)
    }
}
