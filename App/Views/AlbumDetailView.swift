import NaviCore
import SwiftUI

/// Album tracks grouped by disc number.
struct AlbumDetailView: View {
    let albumID: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var detail: AlbumDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let detail {
                    header(detail)

                    actionBar(detail)

                    if detail.songs.isEmpty {
                        NaviPlaceholderView(
                            systemImage: "music.note.list",
                            title: "No tracks",
                            message: "This album has no playable tracks."
                        )
                    } else {
                        trackList(detail.songs)
                    }
                } else if isLoading {
                    NaviPlaceholderView(
                        systemImage: "square.stack",
                        title: "Loading album",
                        isLoading: true
                    )
                } else if let errorMessage {
                    NaviPlaceholderView(
                        systemImage: "wifi.exclamationmark",
                        title: "Could not load album",
                        message: errorMessage
                    )
                }
            }
            .padding(.bottom, 30)
        }
        .task { await load() }
        .navigationTitle(detail?.album.name ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: - Sections

    private func header(_ detail: AlbumDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CoverArtView(
                client: appState.client,
                artID: detail.album.coverArtID,
                cornerRadius: 18,
                placeholderTitle: detail.album.name
            )
            .frame(width: 132, height: 132)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 7)

            VStack(alignment: .leading, spacing: 7) {
                Text(detail.album.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)

                Text(detail.album.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let count = detail.album.songCount {
                        Text(formatCount(count, singular: "track"))
                    }
                    if let year = formatYear(detail.album.year) {
                        Text("·")
                        Text(year)
                    }
                    if let genre = detail.album.genre, !genre.isEmpty {
                        Text("·")
                        Text(genre)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func actionBar(_ detail: AlbumDetail) -> some View {
        HStack(spacing: 10) {
            Button {
                guard let first = detail.songs.first else { return }
                engine.play(first, in: detail.songs)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(GlassButtonStyle(tint: Color.naviAccent, prominent: true))
            .disabled(detail.songs.isEmpty)

            Button {
                engine.shuffle(detail.songs)
            } label: {
                Image(systemName: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 48, height: 44)
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(detail.songs.isEmpty)
        }
        .padding(.horizontal, 16)
    }

    private func trackList(_ songs: [Song]) -> some View {
        let groups = Dictionary(grouping: songs) { song in song.discNumber ?? 1 }

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(groups.keys.sorted(), id: \.self) { disc in
                if groups.keys.count > 1 {
                    Text("Disc \(disc)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                ForEach(groups[disc] ?? []) { song in
                    SongRow(song: song, index: orderedIndex(of: song, in: songs))
                        .contentShape(Rectangle())
                        .onTapGesture { engine.play(song, in: songs) }
                        .contextMenu { songContextMenu(song, allSongs: songs) }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let detail {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let client = appState.client else { return }
                    let shouldStar = detail.album.starred == nil
                    Task {
                        try? await client.setFavourite(id: detail.album.id, favourite: shouldStar)
                        await load()
                    }
                } label: {
                    Image(systemName: detail.album.starred != nil ? "star.fill" : "star")
                        .foregroundStyle(detail.album.starred != nil ? .yellow : .white)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        engine.enqueue(detail.songs)
                    } label: {
                        Label("Add Album to Queue", systemImage: "text.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func songContextMenu(_ song: Song, allSongs: [Song]) -> some View {
        Group {
            Button { engine.play(song, in: allSongs) } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button { engine.playNext([song]) } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            Button { engine.enqueue([song]) } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            Button {
                guard let client = appState.client else { return }
                Task { try? await client.setFavourite(id: song.id, favourite: !(song.isFavourite ?? false)) }
            } label: {
                Label(
                    (song.isFavourite ?? false) ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: (song.isFavourite ?? false) ? "star.slash" : "star"
                )
            }
        }
    }

    /// 1-based track number, falling back to the position in the album.
    private func orderedIndex(of song: Song, in songs: [Song]) -> Int {
        (songs.firstIndex(where: { $0.id == song.id }) ?? 0) + 1
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await client.album(id: albumID)
        } catch {
            errorMessage = appState.describe(error)
        }
    }
}
