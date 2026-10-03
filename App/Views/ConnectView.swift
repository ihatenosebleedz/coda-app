import NaviCore
import SwiftUI

/// Server connection screen. Shown when no credentials are stored.
struct ConnectView: View {
    @EnvironmentObject private var appState: AppState

    @State private var serverText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var apiVersion = "1.16.1"
    @State private var useTokenAuth = true

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header

                GlassSurface(shape: .rect(cornerRadius: 26), tint: nil) {
                    VStack(spacing: 18) {
                        fields
                        connectButton
                    }
                    .padding(22)
                }
                .padding(.horizontal, 20)

                if !appState.recentServers.isEmpty { recentSection }
                if let error = appState.connectionError { errorBanner(error) }
            }
            .padding(.vertical, 34)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 74, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.naviAccent)

            Text("Coda")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("A native Navidrome player")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 40)
    }

    private var fields: some View {
        VStack(spacing: 14) {
            LabeledField(
                title: "Server",
                systemImage: "server.rack",
                text: $serverText,
                style: .url
            )

            LabeledField(
                title: "Username",
                systemImage: "person.fill",
                text: $username,
                style: .username
            )

            LabeledField(
                title: "Password",
                systemImage: "key.fill",
                text: $password,
                style: .password
            )

            DisclosureGroup("Advanced") {
                VStack(spacing: 14) {
                    LabeledField(
                        title: "API version",
                        systemImage: "number",
                        text: $apiVersion,
                        style: .literal
                    )

                    Toggle("Use token authentication", isOn: $useTokenAuth)
                        .tint(Color.naviAccent)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 12)
            }
            .tint(Color.naviAccent)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var connectButton: some View {
        Button {
            Task { await attemptConnect() }
        } label: {
            HStack(spacing: 10) {
                if appState.isConnecting {
                    ProgressView().tint(.white)
                }
                Text(appState.isConnecting ? "Connecting…" : "Connect")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(GlassButtonStyle(tint: Color.naviAccent, prominent: true))
        .disabled(!canConnect || appState.isConnecting)
    }

    private var canConnect: Bool {
        let base = normalizedURL
        return base != nil && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent servers")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 24)

            ForEach(appState.recentServers, id: \.self) { url in
                Button {
                    serverText = url.absoluteString
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Color.naviAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.host() ?? url.absoluteString)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Text(url.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 6)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.14))
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Actions

    /// Users often paste a bare host, so fill in https:// and drop a trailing slash.
    private var normalizedURL: URL? {
        let trimmed = serverText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate), components.host != nil else {
            return nil
        }
        // Navidrome lives at the root; keep any path prefix but drop a bare "/".
        if components.path == "/" { components.path = "" }
        return components.url
    }

    private func attemptConnect() async {
        guard let baseURL = normalizedURL else { return }
        await appState.connect(
            baseURL: baseURL,
            username: username.trimmingCharacters(in: .whitespaces),
            password: password,
            apiVersion: apiVersion.trimmingCharacters(in: .whitespaces),
            useToken: useTokenAuth
        )
    }
}

/// Input traits for a login field, applied to the inner text control.
///
/// These cannot be passed in as trailing modifiers on the wrapper: a wrapper
/// is not a text input, so `textInputAutocapitalization` and friends are
/// unavailable there. Keeping them in an enum also keeps them inside the
/// control the user actually types into.
private enum FieldStyle {
    case literal
    case url
    case username
    case password

    @ViewBuilder
    func apply(to text: String, binding: Binding<String>) -> some View {
        switch self {
        case .literal:
            TextField(text, text: binding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .url:
            TextField(text, text: binding)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textContentType(.URL)
        case .username:
            TextField(text, text: binding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
        case .password:
            SecureField(text, text: binding)
                .textContentType(.password)
        }
    }
}

/// Shared text field chrome for the login form.
private struct LabeledField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var style: FieldStyle = .literal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.naviAccent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                style.apply(to: title, binding: $text)
                    .font(.body)
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.07))
        )
    }
}
