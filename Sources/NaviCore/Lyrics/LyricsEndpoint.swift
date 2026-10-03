import Foundation

public struct RawLyricWord: Decodable, Sendable {
    public let value: String
    public let start: Int?
    public let duration: Int?
}

public struct RawLyricLine: Decodable, Sendable {
    public let startTime: Int?
    public let duration: Int?
    public let value: String?
    public let text: [RawLyricWord]?
}

public struct RawStructuredLyrics: Decodable, Sendable {
    public let line: [RawLyricLine]?
    public let offset: Int?
}

public struct RawLyricsResponse: Decodable, Sendable {
    public let artist: String?
    public let title: String?
    public let value: String?
    public let structuredLyrics: RawStructuredLyrics?
}

extension SubsonicClient {

    public func lyrics(
        songID: String? = nil,
        artist: String? = nil,
        title: String? = nil
    ) async throws -> Lyrics {
        var parameters: [String: String] = [:]
        if let songID { parameters["id"] = songID }
        if let artist { parameters["artist"] = artist }
        if let title { parameters["title"] = title }

        let payload: RawLyricsResponse = try await perform("getLyrics", parameters)

        if let structured = payload.structuredLyrics,
           let rawLines = structured.line,
           !rawLines.isEmpty {
            let parsed = Self.structuredLines(rawLines, offsetMilliseconds: structured.offset ?? 0)
            if !parsed.isEmpty {
                return Lyrics(artist: payload.artist, title: payload.title, lines: parsed)
            }
        }

        if let value = payload.value,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Lyrics(
                artist: payload.artist,
                title: payload.title,
                lines: LRCParser.parse(value).lines
            )
        }

        return Lyrics(artist: payload.artist, title: payload.title, lines: [])
    }

    static func structuredLines(
        _ rawLines: [RawLyricLine],
        offsetMilliseconds: Int
    ) -> [LyricLine] {
        let offset = TimeInterval(offsetMilliseconds) / 1000.0

        return rawLines.compactMap { raw -> LyricLine? in
            let start = max(0, TimeInterval(raw.startTime ?? 0) / 1000.0 - offset)
            let declaredDuration = TimeInterval(raw.duration ?? 0) / 1000.0

            if let texts = raw.text, !texts.isEmpty {
                var cursor = start
                var words: [LyricWord] = []

                for piece in texts {
                    let wordStart = piece.start.map { start + TimeInterval($0) / 1000.0 } ?? cursor
                    let duration = TimeInterval(piece.duration ?? 0) / 1000.0
                    let resolved = duration > 0 ? duration : max(0.2, cursor - wordStart)
                    words.append(
                        LyricWord(text: piece.value, start: wordStart, duration: resolved)
                    )
                    cursor = wordStart + resolved
                }

                return LyricLine(start: start, duration: max(0.1, cursor - start), words: words)
            }

            let text = raw.value ?? ""

            if text.contains("<") {
                let recovered = LRCParser.parse("[\(lrcTimestamp(start))]" + text)
                if let line = recovered.lines.first {
                    return line
                }
            }

            let trimmed = text.trimmingCharacters(in: .whitespaces)

            return LyricLine(
                start: start,
                duration: declaredDuration > 0 ? declaredDuration : 0,
                words: [
                    LyricWord(
                        text: trimmed,
                        start: start,
                        duration: declaredDuration > 0 ? declaredDuration : 0
                    )
                ]
            )
        }
        .sorted { $0.start < $1.start }
    }

    private static func lrcTimestamp(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}