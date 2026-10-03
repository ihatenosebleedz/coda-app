import Foundation

public struct LyricWord: Sendable, Hashable, Identifiable {
    public let id: String
    public let text: String
    public let start: TimeInterval
    public let duration: TimeInterval

    public init(text: String, start: TimeInterval, duration: TimeInterval) {
        self.text = text
        self.start = start
        self.duration = duration
        self.id = "\(Int(start * 1000))-\(text)"
    }

    public var end: TimeInterval { start + duration }

    /// Whether this word is the one being sung at `time`.
    ///
    /// Words with no duration (as produced by line-only LRC) are never
    /// considered active on their own, so callers should fall back to
    /// highlighting the whole line instead.
    public func isActive(at time: TimeInterval) -> Bool {
        guard duration > 0 else { return false }
        return time >= start && time < end
    }
}

public struct LyricLine: Sendable, Hashable, Identifiable {
    public let id: String
    public let start: TimeInterval
    public let duration: TimeInterval
    public let words: [LyricWord]

    public init(start: TimeInterval, duration: TimeInterval, words: [LyricWord]) {
        self.start = start
        self.duration = duration
        self.words = words
        self.id = "\(Int(start * 1000))-\(words.count)"
    }

    public var text: String {
        words.map(\.text).joined()
    }

    public var isWordTimed: Bool {
        words.count > 1 && words.contains { $0.duration > 0 }
    }

    public var end: TimeInterval { start + duration }

    public func wordIndex(at time: TimeInterval) -> Int? {
        guard isWordTimed else { return nil }
        for (index, word) in words.enumerated() where time >= word.start && time < word.start + word.duration {
            return index
        }
        return nil
    }
}

public struct Lyrics: Sendable, Hashable {
    public var artist: String?
    public var title: String?
    public var lines: [LyricLine]

    public init(artist: String? = nil, title: String? = nil, lines: [LyricLine] = []) {
        self.artist = artist
        self.title = title
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }

    public var isSynced: Bool { !lines.isEmpty && lines.contains { $0.start > 0 } }

    public var hasWordTiming: Bool { lines.contains(where: \.isWordTimed) }

    public var plainText: String {
        lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public func lineIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        if time < lines[0].start { return nil }

        var low = 0
        var high = lines.count - 1
        var candidate: Int?

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= time {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        guard let index = candidate else { return nil }
        return index
    }

    public func activeLine(at time: TimeInterval) -> LyricLine? {
        guard let index = lineIndex(at: time) else { return nil }
        return lines[index]
    }

    public func activeWordIndex(at time: TimeInterval) -> Int? {
        activeLine(at: time)?.wordIndex(at: time)
    }

    public var totalDuration: TimeInterval {
        lines.last.map { $0.end } ?? 0
    }
}