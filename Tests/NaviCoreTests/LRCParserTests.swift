import XCTest
@testable import NaviCore

final class LRCParserTests: XCTestCase {

    func testParsesLineLevelTimestamps() {
        let lyrics = LRCParser.parse("""
        [00:12.00]First line
        [00:15.50]Second line
        [01:03.25]Third line
        """)

        XCTAssertEqual(lyrics.lines.count, 3)
        XCTAssertEqual(lyrics.lines.map(\.text), ["First line", "Second line", "Third line"])
        XCTAssertEqual(lyrics.lines[0].start, 12.0, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[1].start, 15.5, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[2].start, 63.25, accuracy: 0.001)
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertFalse(lyrics.hasWordTiming)
    }

    func testParsesWordLevelTimestamps() {
        let lyrics = LRCParser.parse("""
        [00:10.00]<00:10.00>Every <00:10.50>word <00:11.20>moves
        """)

        XCTAssertEqual(lyrics.lines.count, 1)

        let line = lyrics.lines[0]
        XCTAssertTrue(line.isWordTimed)
        XCTAssertTrue(lyrics.hasWordTiming)

        let meaningful = line.words.filter { !$0.text.isEmpty }
        XCTAssertEqual(meaningful.map(\.text), ["Every ", "word ", "moves"])

        XCTAssertEqual(meaningful[0].start, 10.0, accuracy: 0.001)
        XCTAssertEqual(meaningful[1].start, 10.5, accuracy: 0.001)
        XCTAssertEqual(meaningful[2].start, 11.2, accuracy: 0.001)
        XCTAssertEqual(meaningful[0].duration, 0.5, accuracy: 0.001)
        XCTAssertEqual(meaningful[1].duration, 0.7, accuracy: 0.001)
    }

    func testFractionalSecondPrecisionVariants() {
        let lyrics = LRCParser.parse("""
        [00:01.1]one tenth
        [00:02.12]twelve hundredths
        [00:03.123]milliseconds
        """)

        XCTAssertEqual(lyrics.lines[0].start, 1.1, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[1].start, 2.12, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[2].start, 3.123, accuracy: 0.001)
    }

    func testColonAsFractionSeparator() {
        let lyrics = LRCParser.parse("[00:05:50]colon separated")
        XCTAssertEqual(lyrics.lines[0].start, 5.5, accuracy: 0.001)
    }

    func testMetadataTagsAreDiscarded() {
        let lyrics = LRCParser.parse("""
        [ar:Some Artist]
        [ti:Some Title]
        [al:Some Album]
        [by:Navi]
        [length:03:45]
        [00:10.00]Real line
        """)

        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertEqual(lyrics.lines[0].text, "Real line")
    }

    func testOffsetShiftsTimestampsEarlier() {
        let lyrics = LRCParser.parse("""
        [offset:+500]
        [00:11.00]Shifted
        """)

        XCTAssertEqual(lyrics.lines[0].start, 10.5, accuracy: 0.001)
    }

    func testNegativeOffsetShiftsTimestampsLater() {
        let lyrics = LRCParser.parse("""
        [offset:-250]
        [00:11.00]Shifted
        """)

        XCTAssertEqual(lyrics.lines[0].start, 11.25, accuracy: 0.001)
    }

    func testOffsetNeverProducesNegativeTime() {
        let lyrics = LRCParser.parse("""
        [offset:+5000]
        [00:01.00]Clamped
        """)

        XCTAssertEqual(lyrics.lines[0].start, 0, accuracy: 0.001)
    }

    func testUnsyncedLyricsProduceZeroStartLines() {
        let lyrics = LRCParser.parse("""
        Just some plain lyrics
        Across several lines
        """)

        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertFalse(lyrics.isSynced)
        XCTAssertEqual(lyrics.plainText, "Just some plain lyrics\nAcross several lines")
    }

    func testRepeatedTimestampOnOneLineExpandsToMultipleEntries() {
        let lyrics = LRCParser.parse("[00:30.00][01:30.00]Chorus line")

        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines[0].start, 30, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[1].start, 90, accuracy: 0.001)
        XCTAssertTrue(lyrics.lines.allSatisfy { $0.text == "Chorus line" })
    }

    func testLinesAreSortedByTimeRegardlessOfFileOrder() {
        let lyrics = LRCParser.parse("""
        [00:30.00]Third
        [00:10.00]First
        [00:20.00]Second
        """)

        XCTAssertEqual(lyrics.lines.map(\.text), ["First", "Second", "Third"])
    }

    func testBlankLinesAreSkipped() {
        let lyrics = LRCParser.parse("""
        [00:10.00]One

        [00:20.00]Two
        """)

        XCTAssertEqual(lyrics.lines.count, 2)
    }

    func testLineDurationRunsUntilNextLine() {
        let lyrics = LRCParser.parse("""
        [00:10.00]One
        [00:14.00]Two
        """)

        XCTAssertEqual(lyrics.lines[0].duration, 4.0, accuracy: 0.001)
    }

    func testLastLineGetsAFallbackDuration() {
        let lyrics = LRCParser.parse("[00:10.00]Only line")

        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertGreaterThan(lyrics.lines[0].duration, 0)
    }

    func testWindowsLineEndingsAreHandled() {
        let lyrics = LRCParser.parse("[00:10.00]One\r\n[00:20.00]Two\r\n")

        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines[1].text, "Two")
    }

    func testEmptyInputProducesNoLines() {
        XCTAssertTrue(LRCParser.parse("").isEmpty)
        XCTAssertTrue(LRCParser.parse("\n\n\n").isEmpty)
    }

    func testHundredMinuteTimestampsAreParsed() {
        let lyrics = LRCParser.parse("[100:00.00]Very long recording")

        XCTAssertEqual(lyrics.lines[0].start, 6000, accuracy: 0.001)
    }

    func testLineWithWordTagsButNoLineTagIsHandled() {
        let lyrics = LRCParser.parse("<00:10.00>Word <00:10.40>timed <00:11.00>line")

        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertTrue(lyrics.hasWordTiming)
        XCTAssertEqual(lyrics.lines[0].words.filter { !$0.text.isEmpty }.count, 3)
    }

    func testWordDurationsNeverExceedLineEnd() {
        let lyrics = LRCParser.parse("""
        [00:10.00]<00:10.00>One <00:10.50>Two <00:30.00>Stray
        [00:40.00]Next
        """)

        let first = lyrics.lines[0]
        for word in first.words {
            XCTAssertLessThanOrEqual(word.start + word.duration, first.end + 0.001)
        }
    }

    func testWordIsActiveOnlyInsideItsOwnTimeSpan() {
        let word = LyricWord(text: "hello", start: 10, duration: 5)

        XCTAssertFalse(word.isActive(at: 9.9))
        XCTAssertTrue(word.isActive(at: 10))
        XCTAssertTrue(word.isActive(at: 12.5))
        // The end is exclusive so adjacent words do not both light up.
        XCTAssertFalse(word.isActive(at: 15))
        XCTAssertFalse(word.isActive(at: 20))
    }

    func testUntimedWordIsNeverActive() {
        // Line-only LRC gives words a zero duration; the UI must fall back to
        // highlighting the whole line rather than pretend the words are timed.
        let word = LyricWord(text: "whole", start: 3, duration: 0)

        XCTAssertFalse(word.isActive(at: 3))
        XCTAssertFalse(word.isActive(at: 4))
    }

    func testWordTimingMatchesLineTiming() {
        let words = (0..<3).map { LyricWord(text: "w\($0)", start: Double($0) * 10, duration: 10) }
        let line = LyricLine(start: 0, duration: 30, words: words)

        XCTAssertTrue(line.isWordTimed)
        XCTAssertEqual(line.wordIndex(at: 0), 0)
        XCTAssertEqual(line.wordIndex(at: 12), 1)
        XCTAssertEqual(line.wordIndex(at: 25), 2)
        XCTAssertNil(line.wordIndex(at: 30))
    }
}

final class LyricsTests: XCTestCase {

    func testBinarySearchFindsActiveLine() {
        let lyrics = LRCParser.parse("""
        [00:10.00]One
        [00:20.00]Two
        [00:30.00]Three
        """)

        XCTAssertNil(lyrics.activeLine(at: 5))
        XCTAssertEqual(lyrics.activeLine(at: 10)?.text, "One")
        XCTAssertEqual(lyrics.activeLine(at: 19.99)?.text, "One")
        XCTAssertEqual(lyrics.activeLine(at: 20)?.text, "Two")
        XCTAssertEqual(lyrics.activeLine(at: 100)?.text, "Three")
    }

    func testActiveWordIndexTracksWordLevelTiming() {
        let lyrics = LRCParser.parse("""
        [00:10.00]<00:10.00>Alpha <00:11.00>Beta <00:12.00>Gamma
        """)

        XCTAssertEqual(lyrics.activeWordIndex(at: 10.1), 0)
        XCTAssertEqual(lyrics.activeWordIndex(at: 11.5), 1)
        XCTAssertEqual(lyrics.activeWordIndex(at: 5), nil)
    }

    func testWordIndexIsNilForLineOnlyLyrics() {
        let lyrics = LRCParser.parse("[00:10.00]Just a line")
        XCTAssertNil(lyrics.activeWordIndex(at: 11))
    }

    func testTotalDurationIsEndOfLastLine() {
        let lyrics = LRCParser.parse("""
        [00:10.00]One
        [00:20.00]Two
        """)

        XCTAssertEqual(lyrics.totalDuration, lyrics.lines.last?.end)
    }

    func testEmptyLyricsAreSafe() {
        let lyrics = Lyrics()

        XCTAssertTrue(lyrics.isEmpty)
        XCTAssertNil(lyrics.activeLine(at: 10))
        XCTAssertNil(lyrics.activeWordIndex(at: 10))
        XCTAssertEqual(lyrics.totalDuration, 0)
    }
}