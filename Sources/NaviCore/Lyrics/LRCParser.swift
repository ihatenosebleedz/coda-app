import Foundation

public enum LRCParser {

    private static let lineTag = try? NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    )

    private static let wordTag = try? NSRegularExpression(
        pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#
    )

    private static let metadataTag = try? NSRegularExpression(
        pattern: #"^\[([a-zA-Z#]+):(.*)\]$"#
    )

    private static let offsetTag = try? NSRegularExpression(
        pattern: #"^\s*\[offset:\s*([+-]?\d+)\s*\]"#, options: [.caseInsensitive]
    )

    public static func parse(_ raw: String) -> Lyrics {
        let offset = extractOffset(from: raw)
        let normalised = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [LyricLine] = []
        var pendingOffset = offset

        for rawLine in normalised.components(separatedBy: "\n") {
            let (effectiveOffset, consumedOffset) = offsetValue(in: rawLine) ?? (pendingOffset, nil)
            pendingOffset = effectiveOffset

            var working = rawLine
            if let consumedOffset {
                working = rawLine.replacingOccurrences(
                    of: consumedOffset,
                    with: ""
                )
            }

            if isMetadata(working) { continue }

            let timestamps = allLineTimestamps(in: working)
            let body = stripLineTags(from: working)
            let wordStamps = allWordTimestamps(in: body)

            if timestamps.isEmpty {
                if wordStamps.isEmpty {
                    let words = plainWords(from: body, start: 0)
                    if words.isEmpty { continue }
                    lines.append(LyricLine(start: 0, duration: 0, words: words))
                    continue
                }

                let shifted = max(0, (wordStamps.first ?? 0) - effectiveOffset)
                guard let words = parseWords(in: body, defaultStart: shifted, offset: effectiveOffset) else {
                    continue
                }
                lines.append(LyricLine(start: shifted, duration: 0, words: words))
                continue
            }

            for stamp in timestamps {
                let shifted = max(0, stamp - effectiveOffset)

                let words = parseWords(in: body, defaultStart: shifted, offset: effectiveOffset)
                    ?? plainWords(from: body, start: shifted)

                if words.isEmpty { continue }
                lines.append(LyricLine(start: shifted, duration: 0, words: words))
            }
        }

        lines.sort { $0.start < $1.start }
        return Lyrics(lines: withDerivedDurations(lines))
    }

    static func isMetadata(_ line: String) -> Bool {
        guard let metadataTag else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = metadataTag.firstMatch(in: line, options: [], range: range),
              match.range.location == 0 else { return false }

        let key = (line as NSString).substring(with: match.range(at: 1))
        guard let first = key.first else { return false }
        return !first.isNumber
    }

    private static func offsetValue(in line: String) -> (offset: TimeInterval, matched: String)? {
        guard let offsetTag else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = offsetTag.firstMatch(in: line, options: [], range: range) else { return nil }

        let matched = (line as NSString).substring(with: match.range)
        let digits = (line as NSString).substring(with: match.range(at: 1))
        guard let millis = Int(digits) else { return nil }
        return (TimeInterval(millis) / 1000.0, matched)
    }

    private static func extractOffset(from raw: String) -> TimeInterval {
        for line in raw.components(separatedBy: .newlines) {
            if let (value, _) = offsetValue(in: line) {
                return value
            }
        }
        return 0
    }

    private static func allLineTimestamps(in line: String) -> [TimeInterval] {
        guard let lineTag else { return [] }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        return lineTag.matches(in: line, options: [], range: range).compactMap { match in
            timeInterval(from: match, source: ns)
        }
    }

    private static func stripLineTags(from line: String) -> String {
        guard let lineTag else { return line }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result = line

        for match in lineTag.matches(in: line, options: [], range: range).reversed() {
            let swiftRange = Range(match.range, in: result) ?? result.startIndex..<result.startIndex
            result.removeSubrange(swiftRange)
        }

        _ = ns
        return result
    }

    private static func allWordTimestamps(in body: String) -> [TimeInterval] {
        guard let wordTag else { return [] }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        return wordTag.matches(in: body, options: [], range: range).compactMap { match in
            timeInterval(from: match, source: ns)
        }
    }

    private static func parseWords(
        in body: String,
        defaultStart: TimeInterval,
        offset: TimeInterval
    ) -> [LyricWord]? {
        guard let wordTag else { return nil }
        if allWordTimestamps(in: body).isEmpty { return nil }

        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = wordTag.matches(in: body, options: [], range: range)

        guard !matches.isEmpty else { return nil }

        var words: [LyricWord] = []

        for (index, match) in matches.enumerated() {
            guard let rawStamp = timeInterval(from: match, source: ns) else { continue }

            let stamp = max(0, rawStamp - offset)
            let contentStart = match.range.location + match.range.length
            let contentEnd = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            guard contentStart <= contentEnd else { continue }

            let text = ns.substring(
                with: NSRange(location: contentStart, length: contentEnd - contentStart)
            )

            words.append(LyricWord(text: text, start: stamp, duration: 0))
        }

        return words.isEmpty ? nil : words
    }

    private static func plainWords(from body: String, start: TimeInterval) -> [LyricWord] {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return [LyricWord(text: trimmed, start: start, duration: 0)]
    }

    private static func timeInterval(from match: NSTextCheckingResult, source: NSString) -> TimeInterval? {
        guard match.numberOfRanges >= 3 else { return nil }

        let minutes = Int(source.substring(with: match.range(at: 1))) ?? 0
        let seconds = Int(source.substring(with: match.range(at: 2))) ?? 0

        var fraction: Double = 0
        if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
            let raw = source.substring(with: match.range(at: 3))
            guard let value = Double(raw) else { return nil }
            let digits = raw.count
            if digits == 1 {
                fraction = value / 10.0
            } else if digits == 2 {
                fraction = value / 100.0
            } else {
                fraction = value / 1000.0
            }
        }

        return TimeInterval(minutes * 60 + seconds) + fraction
    }

    private static func withDerivedDurations(_ lines: [LyricLine]) -> [LyricLine] {
        var result: [LyricLine] = []

        for (index, line) in lines.enumerated() {
            let lineEnd: TimeInterval
            if index + 1 < lines.count {
                lineEnd = lines[index + 1].start
            } else {
                lineEnd = line.start + max(5.0, Double(line.words.count) * 0.4)
            }

            let boundedEnd = max(line.start + 0.01, lineEnd)
            let lineDuration = boundedEnd - line.start

            var words: [LyricWord] = []
            for (wordIndex, word) in line.words.enumerated() {
                let end: TimeInterval
                if wordIndex + 1 < line.words.count {
                    end = max(word.start + 0.05, line.words[wordIndex + 1].start)
                } else {
                    end = boundedEnd
                }
                let clamped = min(end, boundedEnd)
                words.append(
                    LyricWord(
                        text: word.text,
                        start: word.start,
                        duration: max(0.05, clamped - word.start)
                    )
                )
            }

            if words.isEmpty {
                words = [LyricWord(text: line.text, start: line.start, duration: lineDuration)]
            }

            result.append(
                LyricLine(start: line.start, duration: lineDuration, words: words)
            )
        }

        return result
    }
}