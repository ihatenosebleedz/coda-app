import NaviCore
import SwiftUI

/// Album list with the list-type selector and paging.
struct AlbumsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var albums: [Album] = []
    @State private var listType: AlbumListType = .alphabeticalByName
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var reachedEnd = false

    private let pageSize = 60
    private let columns = [GridItem(.adaptive(minimum: 152, maximum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                listTypePicker
                    .padding(.horizontal, 16)

                if albums.isEmpty && isLoading {
                    NaviPlaceholderView(
                        systemImage: "square.stack",
                        title: "Loading albums",
                        isLoading: true
                    )
                } else if albums.isEmpty, let errorMessage {
                    NaviPlaceholderView(
                        systemImage: "wifi.exclamationmark",
                        title: "Could not load albums",
                        message: errorMessage
                    )
                } else if albums.isEmpty {
                    NaviPlaceholderView(
                        systemImage: "square.stack",
                        title: "No albums",
                        message: "This server has no albums in that view yet."
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(albums) { album in
                            NavigationLink {
                                AlbumDetailView(albumID: album.id)
                            } label: {
                                AlbumGridCell(album: album)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                contextMenu(for: album)
                            }
                            .task {
                                if album.id == albums.last?.id { await loadMore() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    if isLoadingMore {
                        ProgressView().tint(Color.naviAccent).frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await reload() }
        .task { await reload() }
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.large)
    }

    private var listTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AlbumListType.allCases) { type in
                    Button {
                        listType = type
                        Task { await reload() }
                    } label: {
                        Text(type.label)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(listType == type ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(listType == type ? Color.naviAccent : .white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func contextMenu(for album: Album) -> some View {
        Button {
            Task { await play(album) }
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            Task { await playShuffled(album) }
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }

        Button {
            guard let client = appState.client else { return }
            Task {
                if let detail = try? await client.album(id: album.id) {
                    engine.enqueue(detail.songs)
                }
            }
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }

        Divider()

        Button {
            guard let client = appState.client else { return }
            Task { _ = try? await client.setFavourite(albumID: album.id, favourite: album.starred == nil) }
        } label: {
            Label(
                album.starred != nil ? "Remove from Favourites" : "Add to Favourites",
                systemImage: album.starred != nil ? "star.slash" : "star"
            )
        }
    }

    // MARK: - Loading

    private func reload() async {
        reachedEnd = false
        await load(reset: true)
    }

    private func loadMore() async {
        guard !reachedEnd, !isLoadingMore, !isLoading else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard let client = appState.client else { return }

        if reset {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            // byYear needs a range; Navidrome rejects it otherwise.
            let fromYear = listType.requiresYearRange ? 1950 : nil
            let toYear = listType.requiresYearRange ? Calendar.current.component(.year, from: Date()) + 1 : nil

            let page = try await client.albums(
                type: listType,
                size: reset ? pageSize : pageSize,
                offset: reset ? 0 : albums.count,
                fromYear: fromYear,
                toYear: toYear
            )

            albums = reset ? page : albums + page
            if page.count < pageSize { reachedEnd = true }
        } catch {
            if reset { errorMessage = appState.describe(error) }
        }
    }

    private func play(_ album: Album) async {
        guard let client = appState.client,
              let detail = try? await client.album(id: album.id),
              let first = detail.songs.first
        else { return }
        engine.play(first, in: detail.songs)
    }

    private func playShuffled(_ album: Album) async {
        guard let client = appState.client,
              let detail = try? await client.album(id: album.id)
        else { return }
        engine.shuffle(detail.songs)
    }
}

/// Square artwork tile in the album grid.
struct AlbumGridCell: View {
    let album: Album
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CoverArtView(
                client: appState.client,
                artID: album.coverArtID,
                cornerRadius: 16,
                placeholderTitle: album.name
            ) {
                if album.starred != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)

            Text(album.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(album.displaySubtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }
}
