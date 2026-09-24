// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lyricz",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Lyricz", targets: ["SpotifyLyricsBar"])],
    targets: [
        .target(name: "LyricsCore"),
        .executableTarget(name: "SpotifyLyricsBar", dependencies: ["LyricsCore"]),
        .testTarget(name: "LyricsCoreTests", dependencies: ["LyricsCore"]),
        .testTarget(name: "AppTests", dependencies: ["SpotifyLyricsBar"])
    ],
    swiftLanguageModes: [.v5]
)
