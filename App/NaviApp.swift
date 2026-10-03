import SwiftUI

@main
struct NaviApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var engine = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                // Playback must continue with the screen locked.
                .onAppear {
                    UIApplication.shared.beginReceivingRemoteControlEvents()
                }
        }
    }
}
