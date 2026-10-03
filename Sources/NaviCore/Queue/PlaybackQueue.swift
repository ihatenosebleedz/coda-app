import Foundation

public enum RepeatMode: String, Sendable, Hashable, CaseIterable, Identifiable {
    case off
    case all
    case one

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

public struct PlaybackQueue: Sendable {

    public private(set) var entries: [Song] = []
    public private(set) var playOrder: [Int] = []
    public private(set) var cursor: Int?

    public var repeatMode: RepeatMode = .off
    public var isShuffled: Bool = false

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    public var count: Int { entries.count }

    private var resolvedEntryIndex: Int? {
        guard let cursor, playOrder.indices.contains(cursor) else { return nil }
        return playOrder[cursor]
    }

    public var currentSong: Song? {
        guard let entry = resolvedEntryIndex, entries.indices.contains(entry) else { return nil }
        return entries[entry]
    }

    public var upNext: [Song] {
        guard let cursor else { return [] }
        return playOrder.indices
            .filter { $0 > cursor }
            .compactMap { entries.indices.contains(playOrder[$0]) ? entries[playOrder[$0]] : nil }
    }

    public var positionInQueue: Int? { cursor }

    public mutating func setEntries(_ songs: [Song], preservingCurrent: Bool = true) {
        let previouslyPlaying = currentSong?.id

        entries = songs
        playOrder = Array(songs.indices)
        isShuffled = false

        if songs.isEmpty {
            cursor = nil
            return
        }

        if preservingCurrent,
           let previouslyPlaying,
           let index = songs.firstIndex(where: { $0.id == previouslyPlaying }) {
            cursor = playOrder.firstIndex(of: index)
        } else {
            cursor = 0
        }
    }

    public mutating func append(_ songs: [Song]) {
        guard !songs.isEmpty else { return }

        let wasEmpty = entries.isEmpty
        let firstNew = entries.count

        entries.append(contentsOf: songs)
        playOrder.append(contentsOf: Array(firstNew..<entries.count))

        if wasEmpty || cursor == nil {
            cursor = 0
        } else if isShuffled {
            var head = Array(playOrder.prefix(firstNew))
            var tail = Array(playOrder.dropFirst(firstNew))
            tail.shuffle()
            head.append(contentsOf: tail)
            playOrder = head
        }
    }

    public mutating func playNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }

        let newIndices = entries.count..<(entries.count + songs.count)
        entries.append(contentsOf: songs)

        guard let cursor else {
            playOrder = Array(entries.indices)
            self.cursor = 0
            return
        }

        playOrder.insert(contentsOf: newIndices, at: min(cursor + 1, playOrder.count))
    }

    public mutating func removeEntries(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }

        let currentEntry = resolvedEntryIndex
        let wasShuffled = isShuffled

        var remap: [Int: Int] = [:]
        var next = 0
        for index in entries.indices where !offsets.contains(index) {
            remap[index] = next
            next += 1
        }

        let newOrder = playOrder.compactMap { remap[$0] }
        let survivingCurrent = currentEntry.flatMap { remap[$0] }

        var compacted: [Song] = []
        compacted.reserveCapacity(entries.count)
        for (index, song) in entries.enumerated() where !offsets.contains(index) {
            compacted.append(song)
        }
        entries = compacted

        guard !entries.isEmpty else {
            playOrder = []
            cursor = nil
            isShuffled = false
            return
        }

        playOrder = newOrder
        isShuffled = wasShuffled

        if let survivingCurrent, let position = playOrder.firstIndex(of: survivingCurrent) {
            cursor = position
        } else {
            cursor = min(cursor ?? 0, max(0, playOrder.count - 1))
        }
    }

    public mutating func removeSongs(withIDs ids: Set<String>) {
        let offsets = IndexSet(entries.indices.filter { ids.contains(entries[$0].id) })
        removeEntries(at: offsets)
    }

    public mutating func removeDuplicates() {
        var seen = Set<String>()
        let offsets = IndexSet(entries.indices.filter { !seen.insert(entries[$0].id).inserted })
        removeEntries(at: offsets)
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }

        let moving = source.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        guard !moving.isEmpty else { return }

        let currentEntry = resolvedEntryIndex

        var remaining: [Song] = []
        var remap: [Int: Int] = [:]
        var next = 0
        for (index, song) in entries.enumerated() {
            if source.contains(index) { continue }
            remap[index] = next
            next += 1
            remaining.append(song)
        }

        let clamped = min(max(0, destination), remaining.count)
        remaining.insert(contentsOf: moving, at: clamped)

        entries = remaining
        playOrder = Array(entries.indices)

        if let currentEntry, let position = playOrder.firstIndex(of: currentEntry) {
            cursor = position
        } else {
            cursor = min(cursor ?? 0, max(0, playOrder.count - 1))
        }
    }

    /// Entry index of the currently playing song, i.e. the position in the
    /// unshuffled `entries` list that `cursor` points at.
    public var currentEntryIndex: Int? { resolvedEntryIndex }

    /// The song at a queue position, or nil when out of range.
    public func song(atQueuePosition position: Int) -> Song? {
        guard playOrder.indices.contains(position) else { return nil }
        let entry = playOrder[position]
        return entries.indices.contains(entry) ? entries[entry] : nil
    }

    /// Queue position of a specific song, honouring shuffle order.
    public func queuePosition(forSongID id: String) -> Int? {
        guard let entry = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return playOrder.firstIndex(of: entry)
    }

    /// Entries in play order from the current position onward, which is what a
    /// queue list should display (shuffle-aware).
    public var orderedEntries: [Song] {
        playOrder.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    public mutating func jump(toQueuePosition position: Int) {
        guard playOrder.indices.contains(position) else { return }
        cursor = position
    }

    public mutating func jump(toEntryIndex entryIndex: Int) {
        guard entries.indices.contains(entryIndex),
              let position = playOrder.firstIndex(of: entryIndex) else { return }
        cursor = position
    }

    public mutating func advanceForEndOfTrack() -> Song? {
        guard !playOrder.isEmpty else { return nil }

        if repeatMode == .one, let current = currentSong {
            return current
        }

        let next = (cursor ?? -1) + 1

        if playOrder.indices.contains(next) {
            cursor = next
            return currentSong
        }

        if repeatMode == .all {
            cursor = 0
            return currentSong
        }

        return nil
    }

    public mutating func skipToNext() -> Song? {
        guard !playOrder.isEmpty else { return nil }

        let next = (cursor ?? -1) + 1

        if playOrder.indices.contains(next) {
            cursor = next
            return currentSong
        }

        if repeatMode == .all || isShuffled {
            cursor = 0
            return currentSong
        }

        return nil
    }

    public mutating func skipToPrevious(
        currentTime: TimeInterval = 0,
        restartThreshold: TimeInterval = 3
    ) -> Song? {
        guard !playOrder.isEmpty else { return nil }

        if currentTime > restartThreshold, let current = currentSong {
            return current
        }

        let previous = (cursor ?? 0) - 1

        if playOrder.indices.contains(previous) {
            cursor = previous
            return currentSong
        }

        if repeatMode == .all {
            cursor = playOrder.count - 1
            return currentSong
        }

        return currentSong
    }

    public mutating func setShuffled(_ shuffled: Bool) {
        guard shuffled != isShuffled else { return }

        guard !entries.isEmpty else {
            isShuffled = shuffled
            return
        }

        let currentEntry = resolvedEntryIndex

        if shuffled {
            var order = entries.indices.filter { $0 != currentEntry }.shuffled()

            if let currentEntry, entries.indices.contains(currentEntry) {
                order.insert(currentEntry, at: 0)
            }

            playOrder = order
            cursor = 0
        } else {
            playOrder = Array(entries.indices)
            if let currentEntry {
                cursor = playOrder.firstIndex(of: currentEntry)
            }
        }

        isShuffled = shuffled
    }

    public mutating func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }
}