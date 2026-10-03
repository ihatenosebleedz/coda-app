import NaviCore
import SwiftUI

/// Playlists list with create, delete and play actions.
struct PlaylistsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var newName = ""

    var body: some View {
        List {
            if isLoading && playlists.isEmpty {
                NaviPlaceholderView(systemImage: "music.note.list", title: "Loading", isLoading: true)
                    .listRowBackground(Color.clear)
            } else if playlists.isEmpty, let errorMessage {
                NaviPlaceholderView(
                    systemImage: "wifi.exclamationmark",
                    title: "Could not load playlists",
                    message: errorMessage
                )
                .listRowBackground(Color.clear)
            } else if playlists.isEmpty {
                NaviPlaceholderView(
                    systemImage: "music.note.list",
                    title: "No playlists",
                    message: "Tap the plus button to make one."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id)
                    } label: {
                        HStack(spacing: 12) {
                            CoverArtView(
                                client: appState.client,
                                artID: playlist.coverArtID,
                                cornerRadius: 8,
                                placeholderTitle: playlist.name
                            ) {
                                EmptyView()
                            }
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(subtitle(for: playlist))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(playlist) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
        .task { await load() }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = ""; showingCreate = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $showingCreate) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await create() } }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func subtitle(for playlist: Playlist) -> String {
        var parts: [String] = []
        if let count = playlist.songCount {
            parts.append("\(count) track\(count == 1 ? "" : "s")")
        }
        if let duration = playlist.duration, duration > 0 {
            parts.append(formatDuration(duration))
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            playlists = try await client.playlists()
        } catch {
            errorMessage = appState.describe(error)
        }
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let client = appState.client else { return }

        do {
            _ = try await client.createPlaylist(name: name)
            await load()
        } catch {
            errorMessage = appState.describe(error)
        }
    }

    private func delete(_ playlist: Playlist) async {
        guard let client = appState.client else { return }
        do {
            try await client.deletePlaylist(id: playlist.id)
            await load()
        } catch {
            errorMessage = appState.describe(error)
        }
    }
}

/// A playlist's tracks, with removal and play controls.
struct PlaylistDetailView: View {
    let playlistID: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var playlist: Playlist?
    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && songs.isEmpty {
                NaviPlaceholderView(systemImage: "music.note.list", title: "Loading", isLoading: true)
            } else if let errorMessage, songs.isEmpty {
                NaviPlaceholderView(
                    systemImage: "wifi.exclamationmark",
                    title: "Could not load playlist",
                    message: errorMessage
                )
            } else if songs.isEmpty {
                NaviPlaceholderView(
                    systemImage: "music.note.list",
                    title: "Empty playlist",
                    message: "Add songs from any album with Play Next or Add to Queue."
                )
            } else {
                List {
                    Section {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongRow(song: song, index: index + 1)
                                .onTapGesture { engine.play(song, in: songs) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await remove(song) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text("\(songs.count) track\(songs.count == 1 ? "" : "s")")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !songs.isEmpty {
                Button {
                    guard let first = songs.first else { return }
                    engine.play(first, in: songs)
                } label: {
                    Label("Play Playlist", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(GlassButtonStyle(tint: Color.naviAccent, prominent: true))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .task { await load() }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await client.playlist(id: playlistID)
            playlist = result.playlist
            songs = result.songs
        } catch {
            errorMessage = appState.describe(error)
        }
    }

    /// Navidrome removes playlist entries by zero-based index, not by id, so the
    /// index has to be resolved against the currently loaded order. Duplicates
    /// mean every matching index must go, otherwise one copy survives.
    private func remove(_ song: Song) async {
        guard let client = appState.client else { return }

        let indexes = songs.indices.filter { songs[$0].id == song.id }
        guard !indexes.isEmpty else { return }

        do {
            try await client.updatePlaylist(
                playlistID: playlistID,
                songIDsToAdd: [],
                songIndexesToRemove: indexes
            )
            // Update locally rather than refetching: every matching copy is gone.
            songs = songs.enumerated()
                .filter { !indexes.contains($0.offset) }
                .map(\.element)
        } catch {
            errorMessage = appState.describe(error)
            await load()
        }
    }
}
