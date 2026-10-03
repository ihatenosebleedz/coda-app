import Foundation
import Testing

@testable import NaviCore

@Suite("Queue UI accessors")
struct QueueAccessorTests {

    private func songs(_ count: Int) -> [Song] {
        (0..<count).map { index in
            Song(
                id: "s\(index)",
                title: "Track \(index)",
                duration: 200
            )
        }
    }

    @Test("queue position lookup is shuffle aware")
    func queuePositionFollowsPlayOrder() {
        var queue = PlaybackQueue()
        let list = songs(5)
        queue.setEntries(list, preservingCurrent: false)

        #expect(queue.queuePosition(forSongID: "s0") == 0)
        #expect(queue.queuePosition(forSongID: "s4") == 4)

        queue.setShuffled(true)

        // Whatever the shuffled order is, every song must still be locatable
        // and point at the song it claims to.
        for song in list {
            guard let position = queue.queuePosition(forSongID: song.id) else {
                Issue.record("missing queue position for \(song.id)")
                continue
            }
            #expect(queue.song(atQueuePosition: position)?.id == song.id)
        }
    }

    @Test("currentEntryIndex reflects the unshuffled entry")
    func currentEntryIndexSurvivesShuffle() {
        var queue = PlaybackQueue()
        let list = songs(6)
        queue.setEntries(list, preservingCurrent: false)
        queue.setShuffled(true)

        let playing = queue.currentSong
        #expect(playing != nil)
        #expect(playing?.id == list[queue.currentEntryIndex ?? 0].id)
    }

    @Test("song(atQueuePosition:) rejects out of range positions")
    func songAtQueuePositionBounds() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(3), preservingCurrent: false)

        #expect(queue.song(atQueuePosition: 0)?.id == "s0")
        #expect(queue.song(atQueuePosition: 2)?.id == "s2")
        #expect(queue.song(atQueuePosition: 3) == nil)
        #expect(queue.song(atQueuePosition: -1) == nil)
    }

    @Test("orderedEntries is the play order, not the entry order")
    func orderedEntriesRespectsShuffle() {
        var queue = PlaybackQueue()
        let list = songs(4)
        queue.setEntries(list, preservingCurrent: false)

        #expect(queue.orderedEntries.map(\.id) == ["s0", "s1", "s2", "s3"])

        queue.setShuffled(true)
        #expect(queue.orderedEntries.count == 4)
        #expect(Set(queue.orderedEntries.map(\.id)) == Set(list.map(\.id)))
        // The playing track is always played first after shuffling.
        #expect(queue.orderedEntries.first?.id == queue.currentSong?.id)
    }

    @Test("queue position lookup returns nil for unknown songs")
    func queuePositionUnknown() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(2), preservingCurrent: false)
        #expect(queue.queuePosition(forSongID: "nope") == nil)
    }

    @Test("orderedEntries stays consistent after removals and moves")
    func orderedEntriesAfterEdits() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(5), preservingCurrent: false)
        queue.removeEntries(at: IndexSet([1, 3]))

        #expect(queue.orderedEntries.map(\.id) == ["s0", "s2", "s4"])
        #expect(queue.queuePosition(forSongID: "s2") == 1)

        queue.move(fromOffsets: IndexSet([0]), toOffset: 2)
        #expect(queue.orderedEntries.map(\.id) == ["s2", "s4", "s0"])
    }

    @Test("position-based removal deletes the song the list showed")
    func removeSongsAtQueuePositions() {
        var queue = PlaybackQueue()
        let list = songs(5)
        queue.setEntries(list, preservingCurrent: false)
        queue.setShuffled(true)

        // Pick a position from the shuffled play order and remove by position.
        let target = queue.song(atQueuePosition: 2)
        #expect(target != nil)
        queue.removeSongs(atQueuePositions: IndexSet(integer: 2))

        #expect(queue.orderedEntries.map(\.id).contains(target!.id) == false)
        #expect(queue.orderedEntries.count == 4)
    }

    @Test("position-based move reorders play order and keeps songs locatable")
    func moveSongsAtQueuePositions() {
        var queue = PlaybackQueue()
        queue.setEntries(songs(5), preservingCurrent: false)
        queue.setShuffled(true)

        let before = queue.orderedEntries.map(\.id)
        let moved = before[0]
        queue.moveSongs(fromQueuePositions: IndexSet(integer: 0), toQueuePosition: 3)

        let after = queue.orderedEntries.map(\.id)
        #expect(after.count == 5)
        // The moved song is now displayed at the requested position.
        #expect(queue.queuePosition(forSongID: moved) == 3)
        #expect(after[3] == moved)
        // Nothing was lost or duplicated.
        #expect(Set(after) == Set(before))
    }
}
