import NaviCore
import SwiftUI

/// Persistent mini player above the tab bar.
struct MiniPlayerView: View {
    @ObservedObject var engine: PlayerEngine
    /// Invoked when the artwork/title region is tapped.
    var onOpen: () -> Void

    @EnvironmentObject private var appState: AppState

    private var progress: Double {
        guard engine.duration > 0 else { return 0 }
        return min(1, max(0, engine.elapsed / engine.duration))
    }

    var body: some View {
        if let song = engine.currentSong {
            VStack(spacing: 0) {
                // Hairline progress bar across the top of the bar.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(0.10))
                        Rectangle()
                            .fill(Color.naviAccent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    // Only the artwork + text region opens the full player, so
                    // the transport buttons below keep their own hit areas.
                    HStack(spacing: 12) {
                        CoverArtView(
                            client: appState.client,
                            artID: song.coverArtID,
                            cornerRadius: 7,
                            placeholderTitle: song.title
                        ) {
                            EmptyView()
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(song.displayArtist)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen() }
                    .accessibilityAddTraits(.isButton)

                    Spacer(minLength: 4)

                    Button { engine.skipToPrevious() } label: {
                        Image(systemName: "backward.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { engine.skipToNext() } label: {
                        Image(systemName: "forward.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .naviGlass(in: .rect(cornerRadius: 18))
            .padding(.horizontal, 10)
        }
    }
}

/// Editable, reorderable view of the play queue.
struct QueueView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if engine.queue.isEmpty {
                    NaviPlaceholderView(
                        systemImage: "list.bullet",
                        title: "Queue is empty",
                        message: "Play something and it will show up here."
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }

    private var list: some View {
        List {
            if let current = engine.queue.currentSong {
                Section("Now playing") {
                    SongRow(song: current, index: nil)
                        .listRowBackground(Color.white.opacity(0.06))
                }
            }

            Section {
                ForEach(engine.queue.orderedEntries) { song in
                    SongRow(song: song)
                        .onTapGesture { play(song) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                engine.removeSongs(withIDs: [song.id])
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                .onMove { source, destination in
                    engine.moveQueueEntries(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    engine.removeQueueEntries(at: offsets)
                }
            } header: {
                Text("Next up · \(engine.queue.upNext.count) track\(engine.queue.upNext.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func play(_ song: Song) {
        guard let position = engine.queue.queuePosition(forSongID: song.id) else { return }
        engine.jump(to: position)
        dismiss()
    }
}
