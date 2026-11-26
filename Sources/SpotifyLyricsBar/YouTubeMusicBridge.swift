import AppKit
import LyricsCore

/// All browser Apple Events and the selected tab live on one queue.
final class YouTubeMusicBridge: @unchecked Sendable {
    struct Browser: Sendable {
        let id: String
        let name: String
        var safari: Bool { id == "com.apple.Safari" }
    }
    static let browsers = [
        Browser(id: "com.google.Chrome", name: "Google Chrome"),
        Browser(id: "com.apple.Safari", name: "Safari"),
        Browser(id: "com.microsoft.edgemac", name: "Microsoft Edge"),
        Browser(id: "com.brave.Browser", name: "Brave Browser")
    ]
    static var isRunning: Bool {
        browsers.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.id).isEmpty }
    }
    private let queue = DispatchQueue(label: "com.local.lyricz.youtube-music", qos: .utility)
    private struct Target {
        let browser: Browser
        let window: Int
        let tab: Int
        let trackID: String
    }
    private var target: Target?

    func snapshot() async throws -> PlaybackSnapshot? {
        try await perform {
            var readings: [(Target, PlaybackSnapshot)] = []
            var failure: Error?
            for browser in Self.browsers where !NSRunningApplication.runningApplications(withBundleIdentifier: browser.id).isEmpty {
                do {
                    let result = try Self.run(Self.discoveryScript(browser), browser: browser)
                    for index in 1...max(1, result.numberOfItems) {
                        guard let entry = result.atIndex(index),
                              let json = entry.atIndex(3)?.stringValue,
                              let snapshot = try Self.decode(json) else { continue }
                        readings.append((Target(browser: browser, window: Int(entry.atIndex(1)?.int32Value ?? 0),
                                                tab: Int(entry.atIndex(2)?.int32Value ?? 0), trackID: snapshot.track.id), snapshot))
                    }
                } catch { failure = error }
            }
            // Prefer a playing tab; keep the selected tab stable when several are playing.
            let chosen = readings.first { $0.1.isPlaying && self.matches($0.0) }
                ?? readings.first { $0.1.isPlaying }
                ?? readings.first { self.matches($0.0) } ?? readings.first
            self.target = chosen?.0
            if let chosen { return chosen.1 }
            if let failure { throw failure }
            return nil
        }
    }

    private func matches(_ other: Target) -> Bool {
        target?.browser.id == other.browser.id && target?.window == other.window && target?.tab == other.tab
    }

    func send(_ command: PlayerBridge.Command) async throws {
        let operation: String
        switch command {
        case .playPause: operation = Self.clickButton("ytmusic-player-bar #play-pause-button, .ytmusicPlayerControlsPlayPauseButton button")
        case .previous: operation = Self.clickButton("ytmusic-player-bar .previous-button, .ytmusicPlayerControlsPreviousButton button")
        case .next: operation = Self.clickButton("ytmusic-player-bar .next-button, .ytmusicPlayerControlsNextButton button")
        }
        guard try await act(operation, expectedTrack: nil) else {
            throw PlayerError.script(L("A faixa mudou. Selecione um trecho da música atual."))
        }
    }

    private static func clickButton(_ selector: String) -> String {
        "const button = document.querySelector(\(jsonString(selector))); if (!button || button.disabled || button.getAttribute('aria-disabled') === 'true') return false; button.click()"
    }

    func seek(to position: TimeInterval, trackID: String) async throws -> Bool {
        guard position.isFinite, position >= 0 else { return false }
        return try await act(Self.seekJavaScript(position: position), expectedTrack: trackID)
    }

    static func seekJavaScript(position: TimeInterval) -> String {
        let seconds = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), position)
        return """
        const seconds = Math.min(\(seconds), current.snapshot.duration);
        if (current.slider?.tagName === 'INPUT') {
            current.slider.value = String(seconds);
            current.slider.dispatchEvent(new Event('input', {bubbles:true}));
            current.slider.dispatchEvent(new Event('change', {bubbles:true}));
        } else {
            video.currentTime = current.offset + seconds;
        }
        """
    }

    private func act(_ operation: String, expectedTrack: String?) async throws -> Bool {
        try await perform {
            guard let target = self.target else { throw PlayerError.script(L("Abra o YouTube Music em um navegador compatível e dê play.")) }
            let expected = Self.jsonString(expectedTrack ?? target.trackID)
            let js = """
            (() => {
                if (location.origin !== 'https://music.youtube.com') return false;
                \(Self.mediaJavaScript)
                const current = readCurrentMedia();
                if (!current || 'youtubeMusic:' + current.snapshot.id !== \(expected)) return false;
                const video = current.media;
                \(operation);
                return true;
            })()
            """
            return try Self.run(Self.actionScript(target, js: js), browser: target.browser).booleanValue
        }
    }

    private func perform<T: Sendable>(_ action: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    do { continuation.resume(returning: try action()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    static func decode(_ json: String) throws -> PlaybackSnapshot? {
        struct Reading: Decodable {
            let id: String, title: String, artist: String, album: String
            let duration: Double, position: Double
            let playing: Bool
            let artwork: String?
        }
        guard let data = json.data(using: .utf8), json != "null", !json.isEmpty else { return nil }
        let value = try JSONDecoder().decode(Reading.self, from: data)
        guard !value.id.isEmpty, value.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.duration.isFinite, value.duration > 0, value.position.isFinite else { return nil }
        let url = value.artwork.flatMap(URL.init(string:))
        let track = Track(id: "youtubeMusic:" + value.id, title: value.title, artist: value.artist,
                          album: value.album, duration: value.duration,
                          artworkURL: url?.scheme == "https" ? url : nil)
        return PlaybackSnapshot(track: track, isPlaying: value.playing,
                                position: min(value.duration, max(0, value.position)))
    }

    /// Keep playback time and metadata tied to the same media element. YouTube
    /// may retain an old video while a gapless queue item starts on another one.
    static let mediaJavaScript = """
    function readCurrentMedia() {
        if (location.origin !== 'https://music.youtube.com') return null;
        const meta = navigator.mediaSession?.metadata;
        const normalize = value => (value || '').normalize('NFKC').replace(/\\s+/g, ' ').trim().toLowerCase();
        const bar = document.querySelector('ytmusic-player-bar');
        const slider = document.querySelector('.ytMusicMiniPlayerProgressBar, ytmusic-player-bar #progress-bar');
        const sliderNumber = (property, attribute) => {
            const value = slider?.[property] ?? slider?.getAttribute(attribute);
            return value === undefined || value === null || value === '' ? NaN : Number(value);
        };
        const songDuration = sliderNumber('max', 'aria-valuemax');
        const songPosition = sliderNumber('value', 'aria-valuenow');
        // With gapless playback the media element has a cumulative, growing
        // MediaSource timeline. The seek control remains relative to this song.
        if (slider && (!Number.isFinite(songDuration) || songDuration <= 0 ||
            !Number.isFinite(songPosition) || songPosition < 0 || songPosition > songDuration)) return null;
        const candidates = [];
        for (const media of document.querySelectorAll('video, audio')) {
            if (!Number.isFinite(media.duration) || media.duration <= 0 ||
                !Number.isFinite(media.currentTime) || media.readyState === 0 || media.ended) continue;
            const player = media.closest('.html5-video-player') || document.querySelector('#movie_player');
            if (player?.classList.contains('ad-showing')) continue;
            const info = player?.getVideoData?.() || {};
            const link = player?.querySelector('.ytp-title-link');
            const playerTitle = info.title || link?.textContent?.trim();
            // Metadata and the old video are not updated atomically by the site.
            if (meta?.title && playerTitle && normalize(meta.title) !== normalize(playerTitle)) continue;
            const id = info.video_id || link?.href?.match(/[?&]v=([A-Za-z0-9_-]+)/)?.[1];
            // The address bar can still point at the previous song after autoplay.
            // A player-owned identity is required before accepting or controlling it.
            if (!id) continue;
            const title = playerTitle || meta?.title || bar?.querySelector('.title')?.textContent?.trim();
            if (!title) continue;
            const duration = slider ? songDuration : media.duration;
            const position = slider ? songPosition : media.currentTime;
            candidates.push({media, slider, offset: media.currentTime - position, snapshot: {id, title,
                artist: info.author || meta?.artist || bar?.querySelector('.byline a')?.textContent?.trim() || '',
                album: meta?.album || '', duration, position,
                playing: !media.paused && !media.ended,
                artwork: meta?.artwork?.slice(-1)[0]?.src || bar?.querySelector('img')?.src || null}});
        }
        // A hidden video is normal for audio-only playback. Playback state, not
        // visibility or DOM order, selects the current queue item.
        return candidates.find(item => item.snapshot.playing) || candidates[0] || null;
    }
    """

    static let snapshotJavaScript = """
    (() => {
        \(mediaJavaScript)
        const current = readCurrentMedia();
        return JSON.stringify(current?.snapshot || null);
    })()
    """

    // Each script checks the exact HTTPS origin again before touching page state.
    static func discoveryScript(_ browser: Browser) -> String {
        let execute = browser.safari
            ? "do JavaScript \(quote(snapshotJavaScript)) in t"
            : "execute t javascript \(quote(snapshotJavaScript))"
        return """
        using terms from application id "\(browser.id)"
            tell application id "\(browser.id)"
                with timeout of 2 seconds
                    set readings to {}
                    repeat with w in windows
                        set tabIndex to 0
                        repeat with t in tabs of w
                            set tabIndex to tabIndex + 1
                            set tabURL to URL of t
                            if tabURL is "https://music.youtube.com" or tabURL starts with "https://music.youtube.com/" then
                                set songData to \(execute)
                                set end of readings to {id of w, tabIndex, songData}
                            end if
                        end repeat
                    end repeat
                    return readings
                end timeout
            end tell
        end using terms from
        """
    }

    private static func actionScript(_ target: Target, js: String) -> String {
        let execute = target.browser.safari ? "do JavaScript \(quote(js)) in t" : "execute t javascript \(quote(js))"
        return """
        using terms from application id "\(target.browser.id)"
            tell application id "\(target.browser.id)"
                with timeout of 2 seconds
                    set t to tab \(target.tab) of window id \(target.window)
                    set tabURL to URL of t
                    if tabURL is not "https://music.youtube.com" and tabURL does not start with "https://music.youtube.com/" then return false
                    return \(execute)
                end timeout
            end tell
        end using terms from
        """
    }

    private static func run(_ source: String, browser: Browser) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw PlayerError.script(L("Não foi possível preparar a conexão com o player.")) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if CommandLine.arguments.contains("--debug-youtube") {
            NSLog("Lyricz YouTube Music (%@): %@", browser.name, result.description)
        }
        if error != nil {
            throw PlayerError.script(LF("No %@, permita Automação para o Lyricz e ative JavaScript via Apple Events. Consulte as instruções de YouTube Music nos ajustes.", browser.name))
        }
        return result
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    private static func jsonString(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
}
