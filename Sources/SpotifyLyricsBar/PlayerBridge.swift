import AppKit
import LyricsCore

enum PlayerError: LocalizedError {
    case automationDenied(PlayerSource)
    case script(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied(let player): return LF("Permita que o Lyricz acesse o %@ em Ajustes do Sistema → Privacidade e Segurança → Automação.", player.name)
        case .script(let message): return message
        }
    }
}

/// Apple events run on one background queue per player so a slow response cannot freeze the UI.
final class PlayerBridge: @unchecked Sendable {
    let source: PlayerSource
    init(source: PlayerSource) { self.source = source }
    private let queue = DispatchQueue(label: "com.local.spotifylyricsbar.apple-events", qos: .utility)

    enum Command: String {
        case playPause = "playpause"
        case previous = "previous track"
        case next = "next track"
    }

    func snapshot() async throws -> PlaybackSnapshot? {
        try await execute(source == .spotify ? Self.snapshotScript : Self.musicSnapshotScript) { result in
            self.decodeSnapshot(result)
        }
    }

    func decodeSnapshot(_ result: NSAppleEventDescriptor) -> PlaybackSnapshot? {
            guard result.numberOfItems == 8,
                  let id = result.atIndex(1)?.stringValue,
                  let title = result.atIndex(2)?.stringValue,
                  let artist = result.atIndex(3)?.stringValue,
                  let album = result.atIndex(4)?.stringValue,
                  !title.isEmpty else { return nil }
            guard self.source != .spotify || id.hasPrefix("spotify:track:") || id.hasPrefix("spotify:local:") else { return nil }
            // Spotify returns duration in milliseconds, despite the dictionary's description.
            let duration = (result.atIndex(5)?.doubleValue ?? 0) / (self.source == .spotify ? 1000 : 1)
            guard duration > 0, duration.isFinite else { return nil }
            let artwork = result.atIndex(6)?.stringValue.flatMap(URL.init(string:))
            let track = Track(id: self.source == .spotify ? id : "appleMusic:" + id, title: title, artist: artist, album: album,
                              duration: duration, artworkURL: artwork?.scheme == "https" ? artwork : nil)
            let position = result.atIndex(7)?.doubleValue ?? 0
            guard position.isFinite else { return nil }
            return PlaybackSnapshot(track: track, isPlaying: result.atIndex(8)?.booleanValue ?? false,
                                    position: position)
    }

    func send(_ command: Command) async throws {
        let source = """
        with timeout of 5 seconds
            if application id "\(self.source.bundleID)" is running then
                tell application id "\(self.source.bundleID)" to \(command.rawValue)
            end if
        end timeout
        """
        let _: Bool = try await execute(source) { _ in true }
    }

    func seek(to position: TimeInterval, trackID: String) async throws -> Bool {
        guard position.isFinite, position >= 0 else { return false }
        let seconds = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), position)
        let nativeID = source == .appleMusic ? String(trackID.dropFirst("appleMusic:".count)) : trackID
        let escapedID = nativeID.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let source = """
        with timeout of 5 seconds
            if application id "\(self.source.bundleID)" is not running then return false
            tell application id "\(self.source.bundleID)"
                if player state is stopped then return false
                if \(self.source == .spotify ? "id" : "persistent ID") of current track is not "\(escapedID)" then return false
                set player position to \(seconds)
                return true
            end tell
        end timeout
        """
        return try await execute(source) { $0.booleanValue }
    }

    private func execute<T: Sendable>(_ source: String,
                                      transform: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    guard let script = NSAppleScript(source: source) else {
                        continuation.resume(throwing: PlayerError.script(L("Não foi possível preparar a conexão com o player.")))
                        return
                    }
                    var error: NSDictionary?
                    let result = script.executeAndReturnError(&error)
                    if let error {
                        let code = error[NSAppleScript.errorNumber] as? Int
                        if code == -1743 {
                            continuation.resume(throwing: PlayerError.automationDenied(self.source))
                        } else {
                            continuation.resume(throwing: PlayerError.script(
                                error[NSAppleScript.errorMessage] as? String ?? L("O player não respondeu. Tente novamente.")))
                        }
                        return
                    }
                    do { continuation.resume(returning: try transform(result)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    func artwork(trackID: String) async throws -> Data? {
        guard source == .appleMusic else { return nil }
        let nativeID = String(trackID.dropFirst("appleMusic:".count))
        guard !nativeID.isEmpty, nativeID.allSatisfy({ $0.isHexDigit }) else { return nil }
        let script = """
        with timeout of 5 seconds
            if application id "com.apple.Music" is not running then return ""
            tell application id "com.apple.Music"
                if player state is stopped then return ""
                if persistent ID of current track is not "\(nativeID)" then return ""
                try
                    return raw data of artwork 1 of current track
                on error
                    return ""
                end try
            end tell
        end timeout
        """
        return try await execute(script) { result in
            let data = result.data
            return data.count > 100 && data.count <= 8 * 1024 * 1024 ? data : nil
        }
    }

    static let musicSnapshotScript = """
    with timeout of 5 seconds
        if application id "com.apple.Music" is not running then return {}
        tell application id "com.apple.Music"
            if player state is stopped then return {}
            set theTrack to current track
            set trackID to persistent ID of theTrack
            set trackName to name of theTrack
            set trackArtist to artist of theTrack
            set trackAlbum to album of theTrack
            set trackDuration to duration of theTrack
            set trackPosition to player position
            set trackPlaying to player state is playing
            if persistent ID of current track is not trackID then return {}
            return {trackID, trackName, trackArtist, trackAlbum, trackDuration, "", trackPosition, trackPlaying}
        end tell
    end timeout
    """

    private static let snapshotScript = """
    with timeout of 5 seconds
        if application id "com.spotify.client" is not running then return {}
        tell application id "com.spotify.client"
            if player state is stopped then return {}
            set theTrack to current track
            set trackID to id of theTrack
            set trackName to name of theTrack
            set trackArtist to artist of theTrack
            set trackAlbum to album of theTrack
            set trackDuration to duration of theTrack
            set trackArtwork to artwork url of theTrack
            set trackPosition to player position
            set trackPlaying to player state is playing
            if id of current track is not trackID then return {}
            return {trackID, trackName, trackArtist, trackAlbum, trackDuration, trackArtwork, trackPosition, trackPlaying}
        end tell
    end timeout
    """
}
