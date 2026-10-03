import NaviCore
import SwiftUI

/// Full-screen player with artwork, scrubber, transport, queue and lyrics.
struct NowPlayingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                artworkBackdrop

                VStack(spacing: 0) {
                    Spacer(minLength: 10)

                    artwork
                        .padding(.horizontal, 52)
                        .shadow(color: .black.opacity(0.55), radius: 26, y: 14)

                    trackInfo
                        .padding(.top, 30)
                        .padding(.horizontal, 28)

                    Spacer(minLength: 14)

                    scrubber
                        .padding(.horizontal, 28)

                    transport
                        .padding(.top, 22)

                    bottomActions
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Now Playing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showQueue) {
                QueueView()
            }
            .sheet(isPresented: $showLyrics) {
                LyricsSheet(engine: engine)
            }
        }
        .onAppear {
            engine.loadLyrics()
        }
    }

    // MARK: - Pieces

    /// Blurred, scaled artwork behind everything, for depth.
    private var artworkBackdrop: some View {
        CoverArtView(
            client: appState.client,
            artID: engine.currentSong?.coverArtID,
            cornerRadius: 0,
            placeholderTitle: engine.currentSong?.title
        ) {
            EmptyView()
        }
        .ignoresSafeArea()
        .blur(radius: 68)
        .scaleEffect(1.5)
        .opacity(0.62)
    }

    private var artwork: some View {
        CoverArtView(
            client: appState.client,
            artID: engine.currentSong?.coverArtID,
            cornerRadius: 22,
            placeholderTitle: engine.currentSong?.title
        ) {
            EmptyView()
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(engine.currentSong?.title ?? "Not Playing")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(engine.currentSong?.displayArtist ?? "—")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)

            if let codec = engine.currentSong.flatMap({ describeCodec($0) }) {
                Text(codec)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : engine.progress },
                    set: { scrubValue = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = engine.progress
                        isScrubbing = true
                    } else {
                        engine.userDidSeek(to: scrubValue * engine.duration)
                        isScrubbing = false
                    }
                }
            )
            .tint(Color.naviAccent)

            HStack {
                Text(formatDuration(Int(isScrubbing ? scrubValue * engine.duration : engine.elapsed)))
                Spacer()
                Text("-\(formatDuration(Int(max(0, engine.duration - (isScrubbing ? scrubValue * engine.duration : engine.elapsed)))))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var transport: some View {
        HStack(spacing: 30) {
            CircleIconButton(systemImage: "gobackward.15", size: 44, iconSize: 18) {
                engine.skipBackward(seconds: 15)
            }

            CircleIconButton(
                systemImage: engine.isPlaying ? "pause.fill" : "play.fill",
                size: 68,
                iconSize: 27
            ) {
                engine.togglePlayPause()
            }
            .background(
                Circle()
                    .fill(Color.naviAccent.opacity(engine.isPlaying ? 0.9 : 0.75))
                    .shadow(color: Color.naviAccent.opacity(0.5), radius: 16, y: 6)
            )
            .foregroundStyle(.white)

            CircleIconButton(systemImage: "goforward.15", size: 44, iconSize: 18) {
                engine.skipForward(seconds: 15)
            }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 0) {
            CircleIconButton(
                systemImage: (engine.currentSong?.isFavourite ?? false) ? "star.fill" : "star",
                size: 46,
                iconSize: 17
            ) { engine.toggleFavourite() }

            Spacer(minLength: 0)

            TransportControls(engine: engine, size: 36)

            Spacer(minLength: 0)

            Button { showLyrics = true } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lyrics")
        }
        .overlay(alignment: .bottom) {
            // Queue sits below the transport row so it never overlaps it.
            Button { showQueue = true } label: {
                Label("Queue", systemImage: "list.bullet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .offset(y: 34)
        }
    }
}

/// Lyrics presented as a sheet with word-level highlighting.
struct LyricsSheet: View {
    let engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.naviBackgroundTop.ignoresSafeArea()

                if engine.isLoadingLyrics {
                    NaviPlaceholderView(systemImage: "quote.bubble", title: "Loading lyrics", isLoading: true)
                } else if let lyrics = engine.lyrics, !lyrics.isEmpty {
                    LyricsScrollView(lyrics: lyrics, currentTime: engine.elapsed)
                } else {
                    NaviPlaceholderView(
                        systemImage: "quote.bubble",
                        title: "No lyrics",
                        message: "This track has no lyrics on your server."
                    )
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }
}

/// Auto-scrolling lyric view. When the track is playing it follows the current
/// line; pausing freezes the highlight so the user can read ahead.
struct LyricsScrollView: View {
    let lyrics: Lyrics
    let currentTime: TimeInterval

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(lyrics.lines) { line in
                        LyricLineView(
                            line: line,
                            currentTime: currentTime
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 240)
                .padding(.horizontal, 22)
            }
            .onChange(of: activeLineID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var activeLineID: String? {
        lyrics.activeLine(at: currentTime)?.id
    }
}

/// One lyric line, rendering word-level timing as progressive highlighting.
struct LyricLineView: View {
    let line: LyricLine
    let currentTime: TimeInterval

    private var isActive: Bool { line.isActive(at: currentTime) }
    private var isPast: Bool { line.end <= currentTime }

    var body: some View {
        Text(attributedText)
            .font(isActive ? .title3.weight(.bold) : .title3)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isActive ? 1.0 : (isPast ? 0.32 : 0.5))
            .animation(.easeInOut(duration: 0.25), value: isActive)
    }

    private var attributedText: AttributedString {
        // Word-level highlight only makes sense when the words are actually
        // timed; otherwise plain line timing is the best we can show.
        guard line.isWordTimed, isActive else {
            return AttributedString(line.text)
        }

        var result = AttributedString()
        for (offset, word) in line.words.enumerated() {
            let suffix = offset < line.words.count - 1 ? " " : ""
            var piece = AttributedString("\(word.text)\(suffix)")
            // `opacity` is not a valid AttributedString attribute, so the
            // dimming rides on the colour instead.
            piece.foregroundColor = Color.white.opacity(word.isActive(at: currentTime) ? 1.0 : 0.5)
            result.append(piece)
        }
        return result
    }
}

extension LyricLine {
    /// Whether this line should read as currently playing.
    func isActive(at time: TimeInterval) -> Bool {
        time >= start && time < end
    }
}
