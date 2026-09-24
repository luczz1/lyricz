import Foundation

public struct Track: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkURL: URL?

    public init(id: String, title: String, artist: String, album: String,
                duration: TimeInterval, artworkURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
    }
}

public struct LyricLine: Equatable, Identifiable, Sendable {
    public let id: Int
    public let time: TimeInterval
    public let text: String

    public var isInstrumental: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "♪♫♬♩🎵🎶\u{FE0F}"))).isEmpty
    }

    public func playbackPosition(offset: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, time - offset), max(0, duration))
    }
}

public enum LyricMoment: Equatable, Sendable {
    case intro, unavailable, instrumental, words(String)
}

public struct Lyrics: Equatable, Sendable {
    public let lines: [LyricLine]
    public let plainText: String
    public let instrumental: Bool

    public init(synced: String?, plain: String?, instrumental: Bool = false) {
        self.instrumental = instrumental
        lines = instrumental ? [] : LRCParser.parse(synced ?? "")
        plainText = plain?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? lines.map(\.text).joined(separator: "\n")
    }

    public var isAvailable: Bool { instrumental || !lines.isEmpty || !plainText.isEmpty }

    public func moment(at position: TimeInterval) -> LyricMoment {
        if instrumental { return .instrumental }
        guard !lines.isEmpty, position.isFinite else { return .unavailable }
        guard let firstWords = lines.first(where: { !$0.isInstrumental }) else { return .instrumental }
        guard position >= firstWords.time, let line = activeLine(at: position) else { return .intro }
        return line.isInstrumental ? .instrumental : .words(line.text)
    }

    public func activeLine(at position: TimeInterval) -> LyricLine? {
        guard position.isFinite else { return nil }
        // Upper bound finds the latest line, including after a backwards seek.
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? lines[low - 1] : nil
    }
}

public enum LRCParser {
    public static func parse(_ source: String) -> [LyricLine] {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]?\d)(?:[\.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
        let nsSource = source as NSString
        var offset: TimeInterval = 0
        if let match = offsetPattern.firstMatch(in: source, range: NSRange(location: 0, length: nsSource.length)),
           let milliseconds = Double(nsSource.substring(with: match.range(at: 1))) {
            // Positive LRC offset means lyrics should appear earlier.
            offset = milliseconds / 1000
        }
        var entries: [(time: TimeInterval, text: String, order: Int)] = []
        for row in source.components(separatedBy: .newlines) {
            let nsRow = row as NSString
            let matches = timestamp.matches(in: row, range: NSRange(location: 0, length: nsRow.length))
            guard let last = matches.last else { continue }
            let text = nsRow.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(nsRow.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsRow.substring(with: match.range(at: 2))) ?? 0
                let fractionRange = match.range(at: 3)
                let fraction = fractionRange.location == NSNotFound ? 0
                    : (Double("0." + nsRow.substring(with: fractionRange)) ?? 0)
                let time = minutes * 60 + seconds + fraction - offset
                guard time.isFinite else { continue }
                entries.append((time, text, entries.count))
            }
        }
        // Blank timestamps intentionally clear the menu bar during instrumental passages.
        let sorted = entries.sorted { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
        var merged: [(time: TimeInterval, text: String)] = []
        for entry in sorted {
            if let previous = merged.last, previous.time == entry.time {
                if !entry.text.isEmpty && entry.text != previous.text {
                    merged[merged.count - 1].text = [previous.text, entry.text].filter { !$0.isEmpty }.joined(separator: " / ")
                }
            } else {
                merged.append((entry.time, entry.text))
            }
        }
        return merged.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }
}

public struct PlaybackSnapshot: Sendable {
    public let track: Track
    public let isPlaying: Bool
    public let position: TimeInterval
    public let sampledAt: TimeInterval

    public init(track: Track, isPlaying: Bool, position: TimeInterval,
                sampledAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.track = track
        self.isPlaying = isPlaying
        self.position = position
        self.sampledAt = sampledAt
    }

    public func position(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        min(max(0, position + (isPlaying ? max(0, uptime - sampledAt) : 0)), max(0, track.duration))
    }
}
