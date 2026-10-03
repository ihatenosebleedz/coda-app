import NaviCore
import SwiftUI

/// One row in a track list.
struct SongRow: View {
    let song: Song
    var index: Int?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    private var isCurrent: Bool { engine.currentSong?.id == song.id }

    var body: some View {
        HStack(spacing: 12) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.weight(isCurrent ? .bold : .regular))
                    .foregroundStyle(isCurrent ? Color.naviHighlight : .white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(song.displayArtist)

                    if let album = song.album, !album.isEmpty {
                        Text("·")
                        Text(album).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 4)

            if (song.isFavourite ?? false) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow.opacity(0.8))
            }

            Text(formatDuration(song.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? Color.white.opacity(0.08) : .clear)
        )
    }

    @ViewBuilder
    private var leading: some View {
        if let client = appState.client,
           let artID = song.coverArtID,
           ArtworkLoader.shared.cached("song-\(artID)") != nil
        {
            // Reuse the already-loaded album art when we have it, otherwise fall
            // back to the track number so rows stay cheap.
            CoverArtView(client: client, artID: artID, cornerRadius: 6)
                .frame(width: 38, height: 38)
        } else if let index {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 38, height: 38)
        } else {
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 38, height: 38)
        }
    }
}

/// Alphabetically grouped artist list with per-artist track loading.
struct ArtistsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var indexes: [ArtistIndex] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filtered: [ArtistIndex] {
        guard !searchText.isEmpty else { return indexes }
        let query = searchText.lowercased()
        return indexes
            .map { index in
                ArtistIndex(
                    letter: index.letter,
                    artists: index.artists.filter { $0.name.lowercased().contains(query) }
                )
            }
            .filter { !$0.artists.isEmpty }
    }

    private var totalArtists: Int {
        indexes.reduce(0) { $0 + $1.artists.count }
    }

    var body: some View {
        List {
            if isLoading && indexes.isEmpty {
                NaviPlaceholderView(
                    systemImage: "music.mic",
                    title: "Loading artists",
                    isLoading: true
                )
                .listRowBackground(Color.clear)
            } else if indexes.isEmpty, let errorMessage {
                NaviPlaceholderView(
                    systemImage: "wifi.exclamationmark",
                    title: "Could not load artists",
                    message: errorMessage
                )
                .listRowBackground(Color.clear)
            } else if filtered.isEmpty {
                NaviPlaceholderView(
                    systemImage: "magnifyingglass",
                    title: "No matches",
                    message: "No artists match \"\(searchText)\"."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { group in
                    Section {
                        ForEach(group.artists) { artist in
                            NavigationLink {
                                ArtistDetailView(artistID: artist.id, artistName: artist.name)
                            } label: {
                                HStack(spacing: 12) {
                                    CoverArtView(
                                        client: appState.client,
                                        artID: artist.coverArtID,
                                        cornerRadius: 25,
                                        placeholderTitle: artist.name
                                    )
                                    .frame(width: 44, height: 44)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artist.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                        if let count = artist.albumCount {
                                            Text("\(count) album\(count == 1 ? "" : "s")")
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.45))
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text(group.letter.uppercased())
                            .foregroundStyle(Color.naviAccent)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search \(totalArtists) artists")
        .refreshable { await load() }
        .task { await load() }
        .navigationTitle("Artists")
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            indexes = try await client.artistIndex()
        } catch {
            errorMessage = appState.describe(error)
        }
    }
}

/// Top songs plus albums for a single artist.
struct ArtistDetailView: View {
    let artistID: String
    let artistName: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: artistName, subtitle: "Top songs")

                if isLoading {
                    NaviPlaceholderView(systemImage: "music.mic", title: "Loading", isLoading: true)
                } else if songs.isEmpty, let errorMessage {
                    NaviPlaceholderView(
                        systemImage: "wifi.exclamationmark",
                        title: "Could not load songs",
                        message: errorMessage
                    )
                } else if songs.isEmpty {
                    NaviPlaceholderView(
                        systemImage: "music.note",
                        title: "No songs",
                        message: "This artist has no top songs on the server."
                    )
                } else {
                    Button {
                        guard let first = songs.first else { return }
                        engine.play(first, in: songs)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Play \(formatCount(songs.count, singular: "song"))")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(GlassButtonStyle(tint: Color.naviAccent, prominent: true))

                    ForEach(songs) { song in
                        SongRow(song: song)
                            .contentShape(Rectangle())
                            .onTapGesture { engine.play(song, in: songs) }
                            .contextMenu {
                                Button { engine.playNext([song]) } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                Button { engine.enqueue([song]) } label: {
                                    Label("Add to Queue", systemImage: "text.badge.plus")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .task { await load() }
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            songs = try await client.topSongs(artistID: artistID, count: 50)
        } catch {
            errorMessage = appState.describe(error)
        }
    }
}
