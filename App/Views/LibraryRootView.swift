import NaviCore
import SwiftUI

/// Tab container shown once connected: library tabs, mini player, now playing.
struct LibraryRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var selectedTab = Tab.albums
    @State private var showNowPlaying = false
    @State private var backgroundPhase = 0.0

    /// Drives the slow drift of the background blobs.
    private let phaseTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    enum Tab: Hashable {
        case albums, artists, playlists, search, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { AlbumsView() }
                .tabItem { Label("Albums", systemImage: "square.stack") }
                .tag(Tab.albums)

            NavigationStack { ArtistsView() }
                .tabItem { Label("Artists", systemImage: "music.mic") }
                .tag(Tab.artists)

            NavigationStack { PlaylistsView() }
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
                .tag(Tab.playlists)

            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Color.naviAccent)
        // Tap the mini player to open the full-screen player.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView(engine: engine) { showNowPlaying = true }
                .padding(.bottom, 2)
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .background(
            NaviBackground(phase: backgroundPhase)
                .allowsHitTesting(false)
        )
        .onReceive(phaseTimer) { _ in
            backgroundPhase += 0.05
        }
        .onAppear {
            engine.attach(client: appState.client)
        }
        .onChange(of: appState.client?.configuration.baseURL) { _, _ in
            engine.attach(client: appState.client)
        }
    }
}

/// Entry point: shows Connect when signed out, the library otherwise.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.isConnected {
            LibraryRootView()
        } else {
            ConnectView()
        }
    }
}
