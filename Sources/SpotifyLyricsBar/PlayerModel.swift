import AppKit
import Combine
import LyricsCore
import ServiceManagement

enum ConnectionState: Equatable {
    case connecting, playerClosed, waiting, connected, permissionDenied, failure(String)
}

enum LyricsState: Equatable {
    case idle, loading, loaded(Lyrics), unavailable, failure(String)
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var connection: ConnectionState = .connecting
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var lyricsState: LyricsState = .idle
    @Published private(set) var activeLineID: Int?
    @Published private(set) var currentText: String = ""
    @Published private(set) var albumImage: NSImage?
    @Published private(set) var albumPalette: AlbumPalette = .fallback
    @Published var useAlbumColors: Bool {
        didSet { defaults.set(useAlbumColors, forKey: "useAlbumColors") }
    }
    @Published var colorIntensity: Double = 1 {
        didSet { defaults.set(colorIntensity, forKey: "colorIntensity") }
    }
    @Published var floatingLyrics = false
    @Published private(set) var favorites: [FavoriteExcerpt] = []
    @Published private(set) var versions: [LyricsVersion] = []
    @Published private(set) var searchingVersions = false
    @Published private(set) var versionsError: String?
    @Published private(set) var selectedVersionID: Int?
    private var versionsTask: Task<Void, Never>?
    private var chosenVersions: [String: LyricsVersion] = [:]
    var displayPalette: AlbumPalette { useAlbumColors ? albumPalette.intensity(colorIntensity) : .fallback }

    func isFavorite(_ text: String) -> Bool {
        favorites.contains { $0.trackID == track?.id && $0.text == text }
    }

    func favorite(_ text: String) {
        guard let track, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let existing = favorites.first(where: { $0.trackID == track.id && $0.text == text }) {
            removeFavorite(existing.id)
        } else {
            let png = albumImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
            favorites.insert(FavoriteExcerpt(trackID: track.id, title: track.title, artist: track.artist, text: text, artwork: png), at: 0)
            saveFavorites()
        }
    }

    func removeFavorite(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) { defaults.set(data, forKey: "favoriteExcerpts") }
    }

    func searchVersions() {
        versionsTask?.cancel()
        versions = []; versionsError = nil
        guard let track else { searchingVersions = false; return }
        searchingVersions = true
        versionsTask = Task { [weak self, lyricsClient] in
            do {
                let results = try await lyricsClient.search(for: track)
                guard !Task.isCancelled, let self, self.track?.id == track.id else { return }
                self.versions = results; self.searchingVersions = false
            } catch {
                guard !Task.isCancelled, let self, self.track?.id == track.id else { return }
                self.versionsError = error.localizedDescription; self.searchingVersions = false
            }
        }
    }

    func selectVersion(_ version: LyricsVersion?) {
        guard let track else { return }
        lyricsTask?.cancel(); requestID = UUID()
        chosenVersions[track.id] = version
        if let data = try? JSONEncoder().encode(chosenVersions) { defaults.set(data, forKey: "chosenLyricsVersions") }
        selectedVersionID = version?.id
        lyricOffset = 0
        if let version { lyricsState = .loaded(version.lyrics); updateClock() }
        else { loadLyrics(for: track, force: true) }
    }

    @Published var commandError: String?
    @Published var showLyricsInBar: Bool {
        didSet { defaults.set(showLyricsInBar, forKey: "showLyricsInBar") }
    }
    @Published var barWidth: Double {
        didSet { defaults.set(barWidth, forKey: "barWidth") }
    }
    @Published var scrollLongLines: Bool {
        didSet { defaults.set(scrollLongLines, forKey: "scrollLongLines") }
    }
    @Published var scrollSpeed: Double {
        didSet {
            let bounded = MarqueeMotion.clampedSpeed(scrollSpeed)
            if scrollSpeed != bounded {
                scrollSpeed = bounded
                return
            }
            defaults.set(scrollSpeed, forKey: "scrollSpeed")
        }
    }
    @Published var compactInstrumentals: Bool {
        didSet { defaults.set(compactInstrumentals, forKey: "compactInstrumentals") }
    }
    @Published var lyricOffset: Double = 0 {
        didSet {
            if !restoringOffset, let track { offsetStore.save(lyricOffset, for: track.id) }
            updateClock()
        }
    }
    @Published private(set) var isSeeking = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var updatingLogin = false
    @Published private(set) var loginError: String?
    let isDemo: Bool

    private let defaults: UserDefaults
    private let offsetStore: TrackOffsetStore
    private var restoringOffset = false
    private var playbackRevision = 0
    private let bridges = Dictionary(uniqueKeysWithValues: PlayerSource.allCases.map { ($0, PlayerBridge(source: $0)) })
    @Published var playerPreference: PlayerPreference = .automatic {
        didSet {
            defaults.set(playerPreference.rawValue, forKey: "playerPreference")
            if oldValue != playerPreference {
                playbackRevision += 1; previouslyPlaying = []
                if !isDemo { activePlayer = playerPreference.source; clearPlayback(.connecting) }
                reconnect()
            }
        }
    }
    @Published private(set) var activePlayer: PlayerSource?
    @Published private(set) var permissionPlayer: PlayerSource?
    private var deniedPlayers: Set<PlayerSource> = []
    private var previouslyPlaying: Set<PlayerSource> = []
    var playerName: String { (playerPreference.source ?? activePlayer ?? permissionPlayer)?.name ?? "Spotify ou Apple Music" }
    private var bridge: PlayerBridge { bridges[playerPreference.source ?? activePlayer ?? .spotify]! }
    private let lyricsClient = LyricsClient()
    private let artworkService = ArtworkService()
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?
    private var snapshot: PlaybackSnapshot?
    private var pollTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var clockTimer: AnyCancellable?
    private var requestID = UUID()
    private var commandInFlight = false

    init(demo: Bool = false, defaults providedDefaults: UserDefaults? = nil) {
        isDemo = demo
        let defaults = providedDefaults ?? (demo ? UserDefaults(suiteName: "com.local.spotifylyricsbar.demo")! : .standard)
        self.defaults = defaults
        offsetStore = TrackOffsetStore(defaults: defaults)
        playerPreference = defaults.string(forKey: "playerPreference").flatMap(PlayerPreference.init(rawValue:)) ?? .automatic
        colorIntensity = min(1, max(0, defaults.object(forKey: "colorIntensity") as? Double ?? 1))
        favorites = defaults.data(forKey: "favoriteExcerpts").flatMap { try? JSONDecoder().decode([FavoriteExcerpt].self, from: $0) } ?? []
        chosenVersions = defaults.data(forKey: "chosenLyricsVersions").flatMap { try? JSONDecoder().decode([String: LyricsVersion].self, from: $0) } ?? [:]
        useAlbumColors = defaults.object(forKey: "useAlbumColors") as? Bool ?? true
        showLyricsInBar = defaults.object(forKey: "showLyricsInBar") as? Bool ?? true
        scrollLongLines = defaults.object(forKey: "scrollLongLines") as? Bool ?? true
        scrollSpeed = MarqueeMotion.clampedSpeed(
            defaults.object(forKey: "scrollSpeed") as? Double ?? MarqueeMotion.defaultSpeed)
        compactInstrumentals = defaults.object(forKey: "compactInstrumentals") as? Bool ?? true
        let savedWidth = defaults.double(forKey: "barWidth")
        barWidth = savedWidth == 0 ? 260 : min(420, max(120, savedWidth))
    }

    func start() {
        refreshLoginStatus()
        if isDemo { loadDemo() } else { startPolling() }
        clockTimer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.updateClock() }
    }

    func stop() {
        versionsTask?.cancel()
        pollTask?.cancel()
        lyricsTask?.cancel()
        artworkTask?.cancel()
        clockTimer?.cancel()
    }

    var lyrics: Lyrics? {
        if case .loaded(let lyrics) = lyricsState { return lyrics }
        return nil
    }

    var barTitle: String {
        guard let track else {
            return connection == .permissionDenied ? "Permitir \(playerName)" : "Lyricz"
        }
        switch lyricMoment {
        case .words(let text): return text
        case .instrumental: return "♪"
        case .intro, .unavailable: return track.title + " · " + track.artist
        }
    }

    var lyricMoment: LyricMoment { lyrics?.moment(at: position + lyricOffset) ?? .unavailable }
    var isBarCompact: Bool { !showLyricsInBar || (compactInstrumentals && lyricMoment == .instrumental) }
    var statusBarWidth: Double { isBarCompact ? 28 : barWidth }

    func refreshLoginStatus() {
        guard !isDemo else { return }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDemo, !updatingLogin else { return }
        updatingLogin = true
        loginError = nil
        Task {
            defer { updatingLogin = false; refreshLoginStatus() }
            do {
                let service = SMAppService.mainApp
                if enabled {
                    if service.status == .notRegistered || service.status == .notFound { try service.register() }
                } else if service.status != .notRegistered {
                    try await service.unregister()
                }
            } catch { loginError = "Não foi possível alterar o início automático: \(error.localizedDescription)" }
        }
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func seek(to line: LyricLine) {
        guard !isSeeking, !commandInFlight, let track,
              lyrics?.lines.contains(line) == true else { return }
        let target = line.playbackPosition(offset: lyricOffset, duration: track.duration)
        if isDemo {
            snapshot = PlaybackSnapshot(track: track, isPlaying: isPlaying, position: target)
            updateClock()
            return
        }
        let bridge = self.bridge
        isSeeking = true
        playbackRevision += 1
        Task {
            do {
                let accepted = try await bridge.seek(to: target, trackID: track.id)
                if accepted, self.track?.id == track.id, self.activePlayer == bridge.source {
                    snapshot = PlaybackSnapshot(track: track, isPlaying: isPlaying, position: target)
                    updateClock()
                    commandError = nil
                } else {
                    commandError = "A faixa mudou. Selecione um trecho da música atual."
                }
            } catch { commandError = error.localizedDescription }
            isSeeking = false
            await poll()
        }
    }

    func reconnect() {
        guard !isDemo else { return }
        pollTask?.cancel()
        deniedPlayers = []; permissionPlayer = nil
        connection = .connecting
        startPolling()
    }

    func refreshLyrics() {
        if let track, !isDemo { loadLyrics(for: track, force: true) }
    }

    func openPlayer(_ source: PlayerSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else {
            commandError = "Instale o \(source.name) para usar este player."; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func openPreferredPlayer() { openPlayer(playerPreference.source ?? activePlayer ?? .spotify) }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func control(_ command: PlayerBridge.Command) {
        guard !commandInFlight, !isSeeking else { return }
        if isDemo {
            if let snapshot {
                self.snapshot = PlaybackSnapshot(track: snapshot.track,
                    isPlaying: command == .playPause ? !isPlaying : isPlaying,
                    position: command == .playPause ? position : 0)
                isPlaying = self.snapshot?.isPlaying ?? false
            }
            return
        }
        let bridge = self.bridge
        commandInFlight = true
        Task {
            defer { commandInFlight = false }
            do { try await bridge.send(command); commandError = nil }
            catch { commandError = error.localizedDescription }
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                guard !Task.isCancelled else { break }
                let wait: UInt64 = self?.connection == .connected ? 1_000_000_000 : 3_000_000_000
                do { try await Task.sleep(nanoseconds: wait) } catch { break }
            }
        }
    }

    private func poll() async {
        guard !isSeeking else { return }
        let revision = playbackRevision
        let candidates = playerPreference.source.map { [$0] } ?? PlayerSource.allCases
        var readings: [PlayerSource: PlaybackSnapshot] = [:]
        var running = false
        var failure: String?
        for source in candidates {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty else { continue }
            running = true
            guard !deniedPlayers.contains(source) else { continue }
            do {
                if let reading = try await bridges[source]!.snapshot() { readings[source] = reading }
            } catch PlayerError.automationDenied(let denied) {
                deniedPlayers.insert(denied)
            } catch { failure = error.localizedDescription }
            guard !Task.isCancelled, revision == playbackRevision else { return }
        }
        let selected = playerPreference.source ?? PlayerSelection.choose(
            readings: readings, current: activePlayer, previouslyPlaying: previouslyPlaying)
        previouslyPlaying = Set(readings.filter { $0.value.isPlaying }.map(\.key))
        permissionPlayer = candidates.first { deniedPlayers.contains($0) }
        guard let selected, let reading = readings[selected] else {
            activePlayer = playerPreference.source
            if !running { clearPlayback(.playerClosed) }
            else if permissionPlayer != nil { clearPlayback(.permissionDenied) }
            else if let failure { clearPlayback(.failure(failure)) }
            else { clearPlayback(.waiting) }
            return
        }
        let changed = track != reading.track || activePlayer != selected
        activePlayer = selected
        snapshot = reading
        track = reading.track
        isPlaying = reading.isPlaying
        connection = .connected
        if changed {
            versionsTask?.cancel(); versions = []; versionsError = nil; searchingVersions = false
            loadLyrics(for: reading.track)
            loadArtwork(for: reading.track)
            restoreOffset(for: reading.track)
        }
        updateClock()
    }

    private func clearPlayback(_ state: ConnectionState) {
        versionsTask?.cancel(); versions = []; searchingVersions = false; selectedVersionID = nil
        connection = state
        snapshot = nil
        track = nil
        isPlaying = false
        position = 0
        activeLineID = nil
        currentText = ""
        lyricsState = .idle
        requestID = UUID()
        lyricsTask?.cancel()
        artworkTask?.cancel()
        artworkURL = nil
        albumImage = nil
        albumPalette = .fallback
    }

    private func loadArtwork(for track: Track) {
        if activePlayer == .appleMusic {
            artworkTask?.cancel(); artworkURL = nil; albumImage = nil; albumPalette = .fallback
            let music = bridges[.appleMusic]!
            artworkTask = Task { [weak self, artworkService] in
                do {
                    let data = try await music.artwork(trackID: track.id)
                    let artwork: AlbumArtwork?
                    if let data { artwork = try await artworkService.decode(data) } else { artwork = nil }
                    guard !Task.isCancelled, let self, self.track?.id == track.id else { return }
                    self.albumImage = artwork.flatMap { NSImage(data: $0.png) }
                    self.albumPalette = artwork?.palette ?? .fallback
                    self.artworkTask = nil
                } catch {
                    guard !Task.isCancelled, let self, self.track?.id == track.id else { return }
                    self.artworkTask = nil
                }
            }
            return
        }
        guard artworkURL != track.artworkURL || (albumImage == nil && artworkTask == nil) else { return }
        artworkTask?.cancel()
        artworkURL = track.artworkURL
        albumImage = nil
        guard let url = track.artworkURL else { albumPalette = .fallback; return }
        artworkTask = Task { [weak self, artworkService] in
            do {
                let artwork = try await artworkService.load(url)
                guard !Task.isCancelled, let self, self.artworkURL == url else { return }
                self.albumImage = artwork.flatMap { NSImage(data: $0.png) }
                self.albumPalette = artwork?.palette ?? .fallback
                self.artworkTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.artworkURL == url else { return }
                self.albumPalette = .fallback
                self.artworkTask = nil
            }
        }
    }

    private func loadLyrics(for track: Track, force: Bool = false) {
        lyricsTask?.cancel()
        selectedVersionID = chosenVersions[track.id]?.id
        if let selected = chosenVersions[track.id] {
            requestID = UUID()
            lyricsState = .loaded(selected.lyrics)
            return
        }
        let id = UUID()
        requestID = id
        lyricsState = .loading
        activeLineID = nil
        currentText = ""
        lyricsTask = Task { [weak self, lyricsClient] in
            do {
                let result = try await lyricsClient.fetch(for: track, force: force)
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.lyricsState = result.map(LyricsState.loaded) ?? .unavailable
                self.updateClock()
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.lyricsState = .failure(error.localizedDescription)
            }
        }
    }

    private func updateClock() {
        guard let snapshot else { return }
        let nextPosition = snapshot.position()
        if abs(position - nextPosition) > 0.05 { position = nextPosition }
        let line = lyrics?.activeLine(at: nextPosition + lyricOffset)
        if activeLineID != line?.id { activeLineID = line?.id }
        let text = line?.text ?? ""
        if currentText != text { currentText = text }
    }

    private func restoreOffset(for track: Track) {
        restoringOffset = true
        lyricOffset = offsetStore.offset(for: track.id)
        restoringOffset = false
    }

    private func loadDemo() {
        let demoTrack = Track(id: "demo", title: "Entre luzes", artist: "Sessão de demonstração",
                              album: "Uma trilha para o seu dia", duration: 208)
        track = demoTrack
        isPlaying = true
        snapshot = PlaybackSnapshot(track: demoTrack, isPlaying: true, position: 42)
        connection = .connected
        // Original sample text, used only for the offline visual preview.
        lyricsState = .loaded(Lyrics(synced: """
        [00:00.00]
        [00:08.00]A cidade acorda devagar
        [00:18.00]E o dia vem me encontrar
        [00:28.00]Deixo o tempo respirar
        [00:38.00]Há um mundo inteiro lá fora
        [00:50.00]E a música me leva agora
        [01:02.00]Cada passo encontra o seu lugar
        [01:14.00]Entre luzes, vou me encontrar
        [01:28.00]
        [01:38.00]O horizonte muda de cor
        [01:50.00]Levo comigo o que ficou
        [02:02.00]Há um mundo inteiro lá fora
        [02:14.00]E a música me leva agora
        [02:28.00]Cada passo encontra o seu lugar
        [02:42.00]Entre luzes, vou me encontrar
        [03:00.00]
        """, plain: nil))
        if let selected = chosenVersions[demoTrack.id] {
            selectedVersionID = selected.id; lyricsState = .loaded(selected.lyrics)
        }
        restoreOffset(for: demoTrack)
        updateClock()
    }
}
