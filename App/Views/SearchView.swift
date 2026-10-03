import NaviCore
import SwiftUI

/// Search across artists, albums and songs.
struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var query = ""
    @State private var results: SearchResults?
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                NaviPlaceholderView(
                    systemImage: "magnifyingglass",
                    title: "Search your library",
                    message: "Find artists, albums and songs."
                )
            } else if isSearching && results == nil {
                NaviPlaceholderView(systemImage: "magnifyingglass", title: "Searching", isLoading: true)
            } else if let errorMessage {
                NaviPlaceholderView(
                    systemImage: "wifi.exclamationmark",
                    title: "Search failed",
                    message: errorMessage
                )
            } else if let results, results.artists.isEmpty, results.albums.isEmpty, results.songs.isEmpty {
                NaviPlaceholderView(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    message: "Nothing matched \"\(query)\"."
                )
            } else if let results {
                List {
                    if !results.artists.isEmpty {
                        Section("Artists") {
                            ForEach(results.artists) { artist in
                                NavigationLink {
                                    ArtistDetailView(artistID: artist.id, artistName: artist.name)
                                } label: {
                                    Label(artist.name, systemImage: "music.mic")
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }

                    if !results.albums.isEmpty {
                        Section("Albums") {
                            ForEach(results.albums) { album in
                                NavigationLink {
                                    AlbumDetailView(albumID: album.id)
                                } label: {
                                    albumRow(album)
                                }
                            }
                        }
                    }

                    if !results.songs.isEmpty {
                        Section("Songs") {
                            ForEach(results.songs) { song in
                                SongRow(song: song)
                                    .onTapGesture { engine.play(song, in: results.songs) }
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
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Artists, albums, songs")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { _, newValue in
            Task { await search(debounced: newValue) }
        }
        .navigationTitle("Search")
    }

    private func albumRow(_ album: Album) -> some View {
        HStack(spacing: 12) {
            CoverArtView(
                client: appState.client,
                artID: album.coverArtID,
                cornerRadius: 6,
                placeholderTitle: album.name
            ) {
                EmptyView()
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(album.name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(album.displayArtist)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }

    /// Debounces keystrokes so typing does not hammer the server.
    private func search(debounced text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = nil
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        await search(rawQuery: trimmed)
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        await search(rawQuery: trimmed)
    }

    private func search(rawQuery: String) async {
        guard let client = appState.client else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let found = try await client.search(
                query: rawQuery,
                artistCount: 20,
                albumCount: 30,
                songCount: 60
            )
            // Ignore results that arrived after the user moved on.
            guard query.trimmingCharacters(in: .whitespaces) == rawQuery else { return }
            results = found
        } catch is CancellationError {
            return
        } catch {
            errorMessage = appState.describe(error)
        }
    }
}
