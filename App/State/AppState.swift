import Combine
import Foundation
import NaviCore
import SwiftUI

/// Non-secret connection settings, safe to keep in UserDefaults.
struct StoredServer: Codable, Equatable {
    var baseURL: URL
    var username: String
    var apiVersion: String = "1.16.1"
    var useTokenAuthentication: Bool = true

    private static let defaultsKey = "navi.server"

    static func load() -> StoredServer? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(StoredServer.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

/// Audio quality + playback preferences, persisted locally.
struct PlaybackPreferences: Codable, Equatable {
    var quality: AudioQuality = .original
    var scrobbleThresholdPercent: Double = 50

    private static let defaultsKey = "navi.playback"

    static func load() -> PlaybackPreferences {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let prefs = try? JSONDecoder().decode(PlaybackPreferences.self, from: data)
        else { return PlaybackPreferences() }
        return prefs
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// Owns the authenticated client and the connection lifecycle.
///
/// The password lives in the Keychain, never in UserDefaults, so this object
/// can be recreated freely at launch without losing the session.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var client: SubsonicClient?
    @Published private(set) var serverInfo: ServerInfo?
    @Published private(set) var isConnected = false
    @Published var isConnecting = false
    @Published var connectionError: String?

    @Published var preferences = PlaybackPreferences.load() {
        didSet { preferences.save() }
    }

    /// Recent server URL fragments, so reconnecting does not mean retyping.
    @Published private(set) var recentServers: [URL] = {
        UserDefaults.standard.stringArray(forKey: "navi.recentServers")?
            .compactMap(URL.init(string:)) ?? []
    }()

    private let passwordAccount = "server-password"

    init() {
        restore()
    }

    /// Rebuilds a client from stored credentials without showing the login screen.
    func restore() {
        guard let server = StoredServer.load() else { return }
        guard let password = try? Keychain.get(account: passwordAccount),
              let password, !password.isEmpty
        else { return }

        let configuration = ServerConfiguration(
            baseURL: server.baseURL,
            username: server.username,
            password: password,
            apiVersion: server.apiVersion,
            useTokenAuthentication: server.useTokenAuthentication
        )
        client = SubsonicClient(configuration: configuration)
        isConnected = true
        Task { await verifyConnection() }
    }

    /// Attempts a fresh connection with user-supplied credentials.
    func connect(baseURL: URL, username: String, password: String, apiVersion: String, useToken: Bool) async {
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        let configuration = ServerConfiguration(
            baseURL: baseURL,
            username: username,
            password: password,
            apiVersion: apiVersion,
            useTokenAuthentication: useToken
        )

        let candidate = SubsonicClient(configuration: configuration)

        do {
            let info = try await candidate.ping()
            client = candidate
            serverInfo = info
            isConnected = true

            let stored = StoredServer(
                baseURL: baseURL,
                username: username,
                apiVersion: apiVersion,
                useTokenAuthentication: useToken
            )
            stored.save()

            do {
                try Keychain.set(password, account: passwordAccount)
            } catch {
                connectionError = "Signed in, but could not save the password: \(error.localizedDescription)"
            }

            remember(baseURL)
        } catch {
            client = nil
            serverInfo = nil
            isConnected = false
            connectionError = describe(error)
        }
    }

    /// Refreshes the cached server banner without blocking the UI.
    func verifyConnection() async {
        guard let client else { return }
        do {
            serverInfo = try await client.ping()
        } catch {
            // A failed background refresh should not kick the user out mid-session;
            // the next request that needs the server will surface the real error.
            serverInfo = nil
        }
    }

    func signOut() {
        client = nil
        serverInfo = nil
        isConnected = false
        connectionError = nil
        StoredServer.clear()
        try? Keychain.remove(account: passwordAccount)
        ArtworkLoader.shared.clear()
    }

    private func remember(_ url: URL) {
        var list = recentServers.filter { $0 != url }
        list.insert(url, at: 0)
        recentServers = Array(list.prefix(6))
        UserDefaults.standard.set(list.prefix(6).map(\.absoluteString), forKey: "navi.recentServers")
    }

    /// Turns any NaviCore error into something worth showing a user.
    func describe(_ error: Error) -> String {
        if let subsonic = error as? SubsonicError {
            if subsonic.isAuthenticationFailure {
                return "Wrong username or password."
            }
            if subsonic.isRateLimited {
                return "The server is rate-limiting requests. Wait a moment and try again."
            }
            return subsonic.description
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection."
            case .cannotFindHost, .cannotConnectToHost:
                return "Could not reach the server at \(urlError.failingURL?.host() ?? "that address")."
            case .timedOut:
                return "The server took too long to respond."
            case .userAuthenticationRequired:
                return "The server requires credentials."
            default:
                return urlError.localizedDescription
            }
        }

        if let clientError = error as? ClientError {
            return clientError.errorDescription ?? "Request failed."
        }

        return error.localizedDescription
    }
}
