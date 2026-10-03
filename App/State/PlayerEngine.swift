import AVFoundation
import Combine
import Foundation
import MediaPlayer
import NaviCore
import UIKit

/// Playback engine and queue owner.
///
/// Wraps `AVPlayer` because it gives us streaming from arbitrary URLs with the
/// Subsonic auth already baked into the query string, plus reliable remote
/// command and now-playing integration. `PlaybackQueue` from NaviCore owns the
/// ordering, repeat and shuffle semantics so those stay testable off-device.
@MainActor
final class PlayerEngine: NSObject, ObservableObject {
    @Published private(set) var queue = PlaybackQueue()

    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?

    /// Lyrics for the current song, loaded lazily and cleared on track change.
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var isLoadingLyrics = false

    private let player = AVPlayer()
    private weak var client: SubsonicClient?

    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var itemStatusObservations: [NSKeyValueObservation] = []
    private var bufferObservations: [NSKeyValueObservation] = []
    private var lyricTask: Task<Void, Never>?

    /// Guards against firing scrobble/play-count more than once per track.
    private var didSubmitPlayCount = false
    private var lastSubmittedNowPlaying: String?

    /// Artwork for the lock screen / control centre, kept small on purpose.
    private var nowPlayingArtwork: MPMediaItemArtwork?

    var currentSong: Song? { queue.currentSong }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    var canSkipBackward: Bool { queue.positionInQueue.map { $0 > 0 } ?? false }

    override init() {
        super.init()
        configureAudioSession()
        configureRemoteCommands()
        observePlayer()
    }

    /// A time observer must be removed before the player is deallocated, and
/// `deinit` is nonisolated, so the handle is torn down explicitly from
/// `stop()`/`detach` paths rather than touched here.
deinit {
    if let timeObserver {
        // AVPlayer must be reached from the main actor; the observer callback is
        // registered there, so this is always the main thread.
        MainActor.assumeIsolated {
            player.removeTimeObserver(timeObserver)
        }
    }
}

    func attach(client: SubsonicClient?) {
        self.client = client
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            // .playback keeps audio going when the screen locks or the app is
            // backgrounded, which is why Info.plist declares the audio mode.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            errorMessage = "Could not activate audio: \(error.localizedDescription)"
        }
    }

    // MARK: - Observation

    private func observePlayer() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if seconds.isFinite, seconds >= 0 {
                self.elapsed = seconds
                self.updateNowPlayingElapsed()
            }
            // The observer is not view-driven, so the scrobble check has to be
            // driven from here or plays would never be submitted.
            self.evaluateScrobbleThreshold()
        }
    }

    private func observe(item: AVPlayerItem) {
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTrackFinished()
            }
        }

        itemStatusObservations = [
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if item.status == .failed {
                        self.errorMessage = item.error?.localizedDescription ?? "Playback failed."
                        self.isPlaying = false
                        self.isBuffering = false
                    }
                }
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                MainActor.assumeIsolated {
                    self?.isBuffering = !item.isPlaybackLikelyToKeepUp && item.status == .readyToPlay
                }
            }
        ]

        bufferObservations = [
            player.observe(\.isPlaying, options: [.new]) { [weak self] player, _ in
                MainActor.assumeIsolated {
                    self?.isPlaying = player.isPlaying
                }
            }
        ]
    }

    private func handleTrackFinished() {
        guard let next = queue.advanceForEndOfTrack() else {
            isPlaying = false
            updateNowPlayingState()
            return
        }
        load(next, autoplay: true, scrobblePrevious: true)
    }

    // MARK: - Queue mutation

    /// Replaces the queue and starts playing `song` if it is part of it.
    func play(_ song: Song, in songs: [Song]) {
        queue.setEntries(songs, preservingCurrent: false)
        if let index = queue.queuePosition(forSongID: song.id) {
            queue.jump(toQueuePosition: index)
        }
        load(song, autoplay: true)
    }

    /// Replaces the queue and starts at the top.
    func playQueue(_ songs: [Song]) {
        guard let first = songs.first else { return }
        queue.setEntries(songs, preservingCurrent: false)
        load(first, autoplay: true)
    }

    func shuffle(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        queue.setEntries(songs, preservingCurrent: false)
        queue.setShuffled(true)
        if let first = queue.currentSong {
            load(first, autoplay: true)
        }
    }

    func enqueue(_ songs: [Song]) {
        queue.append(songs)
    }

    func playNext(_ songs: [Song]) {
        queue.playNext(songs)
    }

    func removeQueueEntries(at offsets: IndexSet) {
        let removingCurrent = offsets.contains(queue.positionInQueue ?? -1)
        let removedCurrentSong = queue.currentSong

        queue.removeEntries(at: offsets)

        // The cursor shifted under us, so the loaded item no longer matches the
        // queue. If we pulled out the playing track, move to the new occupant.
        if removingCurrent, removedCurrentSong != nil {
            if let replacement = queue.currentSong {
                load(replacement, autoplay: wasPlaying, scrobblePrevious: false)
            } else {
                stop()
            }
        } else {
            refreshNowPlayingMetadata()
        }
    }

    func moveQueueEntries(fromOffsets source: IndexSet, toOffset destination: Int) {
        let currentID = queue.currentSong?.id
        queue.move(fromOffsets: source, toOffset: destination)

        if let currentID, let index = queue.queuePosition(forSongID: currentID),
           let song = queue.song(atQueuePosition: index), song.id != currentSong?.id
        {
            load(song, autoplay: isPlaying, scrobblePrevious: false)
        } else {
            refreshNowPlayingMetadata()
        }
    }

    func jump(to position: Int) {
        queue.jump(toQueuePosition: position)
        guard let song = queue.currentSong else { return }
        load(song, autoplay: true)
    }

    func toggleShuffle() {
        queue.setShuffled(!queue.isShuffled)
        // Shuffling reorders entries but must not interrupt what is playing.
        if let song = queue.currentSong, let index = queue.queuePosition(forSongID: song.id) {
            queue.jump(toQueuePosition: index)
        }
    }

    func cycleRepeatMode() {
        queue.cycleRepeatMode()
    }

    // MARK: - Transport

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            // Restart a finished track before resuming from zero.
            if let song = queue.currentSong, duration > 0, elapsed >= duration - 0.25 {
                elapsed = 0
                load(song, autoplay: true, scrobblePrevious: false)
            } else {
                player.play()
                submitNowPlayingIfNeeded()
            }
        }
        updateNowPlayingState()
    }

    func play() {
        player.play()
        submitNowPlayingIfNeeded()
        updateNowPlayingState()
    }

    func pause() {
        player.pause()
        updateNowPlayingState()
    }

    func skipToNext() {
        guard let next = queue.skipToNext() else { return }
        load(next, autoplay: true, scrobblePrevious: true)
    }

    /// Mirrors the usual behaviour: restart the track unless we are near its start.
    func skipToPrevious() {
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        guard let previous = queue.skipToPrevious(currentTime: 0) else {
            seek(to: 0)
            return
        }
        load(previous, autoplay: true, scrobblePrevious: false)
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlayingElapsed()
    }

    func skipForward(seconds: TimeInterval) { seek(to: elapsed + seconds) }
    func skipBackward(seconds: TimeInterval) { seek(to: elapsed - seconds) }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        clearItemObservers()
        isPlaying = false
        isBuffering = false
        elapsed = 0
        duration = 0
        lyrics = nil
        didSubmitPlayCount = false
        lastSubmittedNowPlaying = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Loading

    private func load(_ song: Song, autoplay: Bool, scrobblePrevious: Bool = false) {
        guard let client else { return }

        if scrobblePrevious {
            submitPlayCount()
        }

        lyricTask?.cancel()
        lyrics = nil
        didSubmitPlayCount = false
        lastSubmittedNowPlaying = nil
        elapsed = 0
        duration = Double(song.duration ?? 0)

        guard let url = client.streamURL(for: song, quality: .original) else {
            errorMessage = "Could not build a stream URL for \(song.title)."
            return
        }

        clearItemObservers()
        let item = AVPlayerItem(url: url)
        observe(item: item)
        player.replaceCurrentItem(with: item)

        // Known duration from metadata lets the scrubber work before the item loads.
        refreshNowPlayingMetadata()

        if autoplay {
            player.play()
            submitNowPlayingIfNeeded()
        }
        updateNowPlayingState()
    }

    /// Applies a quality change to the item that is already loaded.
    func applyQuality(_ quality: AudioQuality) async {
        guard let client, let song = queue.currentSong, song.isVideo == false else { return }
        guard let url = client.streamURL(for: song, quality: quality) else { return }

        let resumeAt = elapsed
        let wasPlaying = isPlaying

        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        if wasPlaying { player.play() }
    }

    private func clearItemObservers() {
        itemStatusObservations.forEach { $0.invalidate() }
        itemStatusObservations.removeAll()
        bufferObservations.forEach { $0.invalidate() }
        bufferObservations.removeAll()
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
    }

    // MARK: - Lyrics

    func loadLyrics() {
        lyricTask?.cancel()

        guard let client, let song = queue.currentSong else { return }
        let songID = song.id

        isLoadingLyrics = true
        lyricTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.lyrics(songID: songID)
                guard !Task.isCancelled, self.queue.currentSong?.id == songID else { return }
                self.lyrics = result
            } catch {
                guard !Task.isCancelled else { return }
                self.lyrics = Lyrics()
            }
            self.isLoadingLyrics = false
        }
    }

    // MARK: - Scrobbling

    private func submitNowPlayingIfNeeded() {
        guard let client, let song = queue.currentSong else { return }
        guard lastSubmittedNowPlaying != song.id else { return }
        lastSubmittedNowPlaying = song.id

        Task { try? await client.nowPlaying(song: song) }
    }

    /// Sends a play scrobble once the listener passes the configured threshold.
    private func submitPlayCount() {
        guard let client, let song = queue.currentSong, !didSubmitPlayCount else { return }
        didSubmitPlayCount = true
        Task { try? await client.scrobble(songs: [song], submission: true) }
    }

    /// Called from the scrubber; fires the play-count scrobble on a real seek.
    func userDidSeek(to seconds: TimeInterval) {
        seek(to: seconds)
        guard duration > 0 else { return }
        let threshold = max(4, duration * 0.5)
        if seconds >= threshold {
            submitPlayCount()
        } else {
            didSubmitPlayCount = false
        }
    }

    /// Fires the play-count scrobble once half the track has elapsed, so simply
    /// listening through still registers a play.
    func evaluateScrobbleThreshold() {
        guard let song = queue.currentSong, !didSubmitPlayCount else { return }

        let total = Double(song.duration ?? 0)
        guard total > 0 else { return }

        // Very short tracks should not wait 4s of a 2s clip.
        let threshold = min(total * 0.5, max(1, total - 1))
        guard elapsed >= threshold else { return }

        submitPlayCount()
    }

    func toggleFavourite() {
        guard let client, let song = queue.currentSong else { return }
        let target = !(song.isFavourite ?? false)
        Task {
            do {
                try await client.setFavourite(id: song.id, favourite: target)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Now Playing / remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPrevious()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: positionEvent.positionTime)
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 15)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 15)
            return .success
        }
        center.changeRepeatModeCommand.supportedRepeatModes = [.off, .all, .one]
        center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let repeatEvent = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }
            switch repeatEvent.repeatType {
            case .all: self?.queue.repeatMode = .all
            case .one: self?.queue.repeatMode = .one
            default: self?.queue.repeatMode = .off
            }
            return .success
        }
        center.changeShuffleModeCommand.supportedShuffleModes = [.off, .items]
        center.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let shuffleEvent = event as? MPChangeShuffleModeCommandEvent else {
                return .commandFailed
            }
            let shouldShuffle = shuffleEvent.shuffleType != .off
            if self?.queue.isShuffled != shouldShuffle {
                self?.toggleShuffle()
            }
            return .success
        }
    }

    /// Rebuilds the lock-screen / control-centre dictionary for the current song.
    func refreshNowPlayingMetadata() {
        guard let song = queue.currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.displayArtist
        if let album = song.album, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        let durationSeconds = Double(song.duration ?? 0)
        if durationSeconds > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
        }

        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        Task { [weak self] in
            await self?.loadNowPlayingArtwork(for: song)
        }
    }

    /// Cover art on the lock screen is small, so a 300px download is plenty.
    private func loadNowPlayingArtwork(for song: Song) async {
        guard let client,
              let artID = song.coverArtID,
              let url = client.coverArtURL(id: artID, size: 300),
              let image = await ArtworkLoader.shared.image(for: "np-\(artID)", url: url, maxPixelSize: 300)
        else { return }

        guard queue.currentSong?.id == song.id else { return }

        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        nowPlayingArtwork = artwork

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo, !info.isEmpty else { return }
        var updated = info
        updated[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        if duration > 0 { updated[MPMediaItemPropertyPlaybackDuration] = duration }
        updated[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
    }

    private func updateNowPlayingState() {
        updateNowPlayingElapsed()
    }
}
