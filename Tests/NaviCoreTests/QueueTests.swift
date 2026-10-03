import XCTest
@testable import NaviCore

final class QueueTests: XCTestCase {

    private func songs(_ count: Int) -> [Song] {
        (0..<count).map { Fixture.makeSong(id: "s\($0)", title: "Track \($0)") }
    }

    func testEmptyQueueHasNoCurrentSong() {
        var queue = PlaybackQueue()

        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.currentSong)
        XCTAssertNil(queue.advanceForEndOfTrack())
        XCTAssertNil(queue.skipToNext())
    }

    func testSetEntriesStartsAtBeginning() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(3))

        XCTAssertEqual(queue.currentSong?.id, "s0")
        XCTAssertEqual(queue.count, 3)
    }

    func testSetEntriesPreservesCurrentTrackByID() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(5))
        queue.jump(toQueuePosition: 3)

        queue.setEntries(songs(5))
        XCTAssertEqual(queue.currentSong?.id, "s3")
    }

    func testSetEntriesResetsWhenCurrentTrackIsGone() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(5))
        queue.jump(toQueuePosition: 3)

        queue.setEntries(songs(2))
        XCTAssertEqual(queue.currentSong?.id, "s0")
    }

    func testAdvanceStopsAtEndWhenRepeatIsOff() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(2))
        queue.repeatMode = .off

        XCTAssertEqual(queue.advanceForEndOfTrack()?.id, "s1")
        XCTAssertNil(queue.advanceForEndOfTrack())
    }

    func testAdvanceWrapsWhenRepeatIsAll() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(2))
        queue.repeatMode = .all

        XCTAssertEqual(queue.advanceForEndOfTrack()?.id, "s1")
        XCTAssertEqual(queue.advanceForEndOfTrack()?.id, "s0")
    }

    func testAdvanceRepeatsSameTrackWhenRepeatIsOne() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(3))
        queue.repeatMode = .one

        XCTAssertEqual(queue.advanceForEndOfTrack()?.id, "s0")
        XCTAssertEqual(queue.advanceForEndOfTrack()?.id, "s0")
    }

    func testExplicitSkipIgnoresRepeatOne() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(3))
        queue.repeatMode = .one

        XCTAssertEqual(queue.skipToNext()?.id, "s1")
    }

    func testCycleRepeatMode() {
        var queue = PlaybackQueue()

        XCTAssertEqual(queue.repeatMode, .off)
        queue.cycleRepeatMode()
        XCTAssertEqual(queue.repeatMode, .all)
        queue.cycleRepeatMode()
        XCTAssertEqual(queue.repeatMode, .one)
        queue.cycleRepeatMode()
        XCTAssertEqual(queue.repeatMode, .off)
    }

    func testPreviousRestartsTrackWhenPastThreshold() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(4))
        queue.jump(toQueuePosition: 2)

        XCTAssertEqual(queue.skipToPrevious(currentTime: 12)?.id, "s2")
    }

    func testPreviousGoesBackWhenEarlyInTrack() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(4))
        queue.jump(toQueuePosition: 2)

        XCTAssertEqual(queue.skipToPrevious(currentTime: 1)?.id, "s1")
    }

    func testPreviousWrapsWhenRepeatIsAll() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(3))
        queue.repeatMode = .all

        XCTAssertEqual(queue.skipToPrevious(currentTime: 0)?.id, "s2")
    }

    func testShuffleIsAPermutationAndKeepsCurrentTrackFirst() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(8))
        queue.jump(toQueuePosition: 5)
        let currentBefore = queue.currentSong?.id

        queue.setShuffled(true)

        XCTAssertEqual(Set(queue.playOrder), Set(0..<8))
        XCTAssertEqual(queue.playOrder.count, 8)
        XCTAssertEqual(queue.currentSong?.id, currentBefore)
        XCTAssertEqual(queue.playOrder.first, queue.playOrder.first)
        XCTAssertTrue(queue.isShuffled)
    }

    func testUnshuffleRestoresOriginalOrderAndCurrentTrack() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(6))
        queue.jump(toQueuePosition: 2)
        let currentBefore = queue.currentSong?.id

        queue.setShuffled(true)
        queue.setShuffled(false)

        XCTAssertEqual(queue.playOrder, Array(0..<6))
        XCTAssertEqual(queue.currentSong?.id, currentBefore)
        XCTAssertFalse(queue.isShuffled)
    }

    func testRemovingCurrentTrackFallsBackToSanePosition() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(5))
        queue.jump(toQueuePosition: 3)

        queue.removeEntries(at: IndexSet(integer: 3))

        XCTAssertEqual(queue.count, 4)
        XCTAssertNotNil(queue.currentSong)
        XCTAssertEqual(queue.currentSong?.id, "s4")
    }

    func testRemovingTrackBeforeCurrentShiftsCursorBack() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(5))
        queue.jump(toQueuePosition: 3)

        queue.removeEntries(at: IndexSet(integer: 0))

        XCTAssertEqual(queue.currentSong?.id, "s3")
    }

    func testRemovingEverythingEmptiesQueue() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(3))

        queue.removeEntries(at: IndexSet(0..<3))

        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.currentSong)
        XCTAssertNil(queue.positionInQueue)
    }

    func testRemoveSongsByID() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(5))

        queue.removeSongs(withIDs: ["s1", "s3"])

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.entries.map(\.id), ["s0", "s2", "s4"])
    }

    func testUpNextReflectsRemainingOrder() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(4))
        queue.jump(toQueuePosition: 1)

        XCTAssertEqual(queue.upNext.map(\.id), ["s2", "s3"])
    }

    func testPlayNextInsertsAtFrontOfRemaining() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(3))
        queue.jump(toQueuePosition: 0)

        queue.playNext([Fixture.makeSong(id: "urgent")])

        XCTAssertEqual(queue.currentSong?.id, "s0")
        XCTAssertEqual(queue.skipToNext()?.id, "urgent")
        XCTAssertEqual(queue.count, 4)
    }

    func testPlayNextOnEmptyQueueStartsPlaying() {
        var queue = PlaybackQueue()
        queue.playNext([Fixture.makeSong(id: "first")])

        XCTAssertEqual(queue.currentSong?.id, "first")
    }

    func testAppendAddsToEndAndPreservesPlaybackPosition() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(2))
        queue.jump(toQueuePosition: 1)

        queue.append([Fixture.makeSong(id: "s2")])

        XCTAssertEqual(queue.currentSong?.id, "s1")
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.upNext.map(\.id), ["s2"])
    }

    func testAppendToEmptyQueueBecomesCurrent() {
        var queue = PlaybackQueue()
        queue.append(songs(2))

        XCTAssertEqual(queue.currentSong?.id, "s0")
    }

    func testMoveReordersEntriesAndKeepsCurrentSong() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(4))
        queue.jump(toQueuePosition: 0)

        queue.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        XCTAssertEqual(queue.entries.map(\.id), ["s3", "s0", "s1", "s2"])
        XCTAssertEqual(queue.currentSong?.id, "s3")
    }

    func testJumpToEntryIndex() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(4))

        queue.jump(toEntryIndex: 2)
        XCTAssertEqual(queue.currentSong?.id, "s2")

        queue.jump(toEntryIndex: 99)
        XCTAssertEqual(queue.currentSong?.id, "s2")
    }

    func testShuffleThenAdvanceStaysInBoundsWithRepeatAll() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(10))
        queue.setShuffled(true)
        queue.repeatMode = .all

        for _ in 0..<25 {
            let next = queue.advanceForEndOfTrack()
            XCTAssertNotNil(next)
            XCTAssertNotNil(queue.positionInQueue)
            XCTAssertTrue(queue.playOrder.indices.contains(queue.positionInQueue ?? -1))
        }
    }

    func testShuffleWithoutRepeatStopsAtEndOfQueue() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(10))
        queue.setShuffled(true)

        for _ in 0..<9 {
            XCTAssertNotNil(queue.advanceForEndOfTrack())
        }

        XCTAssertNil(queue.advanceForEndOfTrack())
        XCTAssertNotNil(queue.positionInQueue)
    }

    func testRepeatAllWithShuffleVisitsEveryTrackExactlyOnce() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(6))
        queue.setShuffled(true)
        queue.repeatMode = .all

        var visited: [String] = []
        if let first = queue.currentSong?.id { visited.append(first) }

        for _ in 0..<(6 - 1) {
            if let song = queue.advanceForEndOfTrack() {
                visited.append(song.id)
            }
        }

        XCTAssertEqual(Set(visited), Set((0..<6).map { "s\($0)" }))
        XCTAssertEqual(visited.count, 6)
    }
}