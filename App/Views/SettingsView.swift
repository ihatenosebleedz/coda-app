import NaviCore
import SwiftUI

/// Quality, account and diagnostics settings.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: PlayerEngine

    @State private var nowPlaying = false
    @State private var errorMessage: String?

    private static let qualities: [AudioQuality] = [.original, .lossless, .high, .medium, .low]

    var body: some View {
        Form {
            Section("Streaming Quality") {
                Picker("Quality", selection: $appState.preferences.quality) {
                    ForEach(Self.qualities) { quality in
                        VStack(alignment: .leading) {
                            Text(quality.label)
                            Text(quality.detail).font(.caption)
                        }
                        .tag(quality)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: appState.preferences.quality) { _, quality in
                    Task { await engine.applyQuality(quality) }
                }
            }

            Section {
                Toggle("Scrobble Now Playing", isOn: $nowPlaying)
                    .onChange(of: nowPlaying) { _, _ in }
            } header: {
                Text("Scrobbling")
            } footer: {
                Text("Coda sends a play scrobble once you pass the halfway point of a track, and sends 'now playing' as soon as playback starts.")
            }

            Section("Server") {
                LabeledContent("Server", value: appState.client.map { "\($0.configuration.baseURL.host() ?? $0.configuration.baseURL.absoluteString)" } ?? "—")
                LabeledContent("Username", value: appState.client?.configuration.username ?? "—")
                LabeledContent("API version", value: appState.client?.configuration.apiVersion ?? "—")

                if let info = appState.serverInfo {
                    LabeledContent("Server version", value: info.serverVersion ?? "unknown")
                    LabeledContent("Type", value: info.serverType ?? "unknown")
                    LabeledContent("OpenSubsonic", value: info.supportsOpenSubsonic ? "Yes" : "No")
                }

                Button("Refresh Connection Info") {
                    Task { await appState.verifyConnection() }
                }
            }

            Section("Maintenance") {
                LabeledContent("Tracks queued", value: "\(engine.queue.count)")
                LabeledContent("Repeat", value: engine.queue.repeatMode.rawValue.capitalized)
                LabeledContent("Shuffle", value: engine.queue.isShuffled ? "On" : "Off")

                Button("Clear Artwork Cache") {
                    ArtworkLoader.shared.clear()
                }

                Button("Clear Playback Queue") {
                    engine.stop()
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    engine.stop()
                    appState.signOut()
                }
            } footer: {
                Text("Removes the saved server and deletes the stored password from the keychain.")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coda 0.1.0")
                        .font(.footnote.weight(.semibold))
                    Text("A native Navidrome client. Built with SwiftUI.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { nowPlaying = true }
    }
}

/// Shown when the server rejects our credentials or goes away mid-session.
struct ConnectionFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            Text("Connection lost")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Retry", action: onRetry)
                .buttonStyle(GlassButtonStyle(tint: Color.naviAccent, prominent: true))
                .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NaviBackground(phase: 0))
    }
}
