import Foundation
import XCTest
@testable import NaviCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// End-to-end checks against a real Navidrome server.
///
/// Run with credentials in the environment:
///
///     NAVI_URL=https://host:4533 NAVI_USER=me NAVI_PASS=secret \
///       ./scripts/naviswift test --filter NaviIntegrationTests
///
/// The suite skips itself when the variables are absent, so `swift test` stays
/// green offline. Credentials are only read from the environment and are never
/// printed: every logged URL is stripped of `u`, `t`, `p` and `s` parameters.
final class NaviIntegrationTests: XCTestCase {

    private var client: SubsonicClient!
    private var failures: [String] = []
    private var performed = 0

    private var folders: [MusicFolder] = []
    private var index: [ArtistIndex] = []
    private var albums: [String: Int] = [:]
    private var sampleAlbum: Album?
    private var songs: [Song] = []
    private var subject: Song?
    private var playlistID: String?

    override func setUpWithError() throws {
        try super.setUpWithError()

        let environment = ProcessInfo.processInfo.environment

        func value(_ key: String) -> String? {
            guard let raw = environment[key] else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard let urlString = value("NAVI_URL"),
              let username = value("NAVI_USER"),
              let password = value("NAVI_PASS") else {
            throw XCTSkip("set NAVI_URL, NAVI_USER and NAVI_PASS to run server integration checks")
        }

        guard let baseURL = ServerConfiguration.normalise(urlString: urlString) else {
            return XCTFail("NAVI_URL is not a valid URL: \(urlString)")
        }

        client = SubsonicClient(
            configuration: ServerConfiguration(baseURL: baseURL, username: username, password: password)
        )
    }

    override func tearDown() {
        client = nil
        super.tearDown()
    }

    // MARK: - Harness

    private func sanitised(_ url: URL?) -> String {
        guard let url else { return "nil" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.filter { !["u", "t", "p", "s"].contains($0.name) }
        return components.string ?? url.absoluteString
    }

    private func fetch(_ url: URL, limit: Int = 2048) async throws -> (bytes: Int, type: String?) {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(limit - 1)", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 || http?.statusCode == 206 else {
            throw HarnessError("HTTP \(http?.statusCode ?? 0) for \(sanitised(url))")
        }
        return (data.count, http?.value(forHTTPHeaderField: "Content-Type"))
    }

    private struct HarnessError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw HarnessError(message) }
    }

    @discardableResult
    private func step(_ name: String, _ body: () async throws -> String?) async -> Bool {
        performed += 1
        do {
            let detail = try await body()
            print("  ok   \(name)\(detail.map { " — \($0)" } ?? "")")
            return true
        } catch {
            failures.append(name)
            XCTFail("\(name): \(error)")
            return false
        }
    }

    // MARK: - Checks

    func testAgainstLiveServer() async throws {
        var serverInfo: ServerInfo?

        print("\nconnection")
        await step("ping") {
            serverInfo = try await client.ping()
            let info = serverInfo!
            return "\(info.serverType ?? "?") \(info.serverVersion ?? "?"), openSubsonic=\(info.supportsOpenSubsonic)"
        }

        guard serverInfo != nil else {
            return XCTFail("no connection, stopping")
        }

        print("\nbrowse")
        await step("getMusicFolders") {
            folders = try await client.musicFolders()
            return "\(folders.count) folder(s): \(folders.map(\.name).joined(separator: ", "))"
        }

        await step("getIndexes") {
            index = try await client.artistIndex()
            let artists = index.flatMap(\.artists)
            return "\(index.count) letter(s), \(artists.count) artist(s)"
        }

        await step("getAlbumList2 across list types") {
            var parts: [String] = []
            for type in AlbumListType.allCases {
                let result = try await client.albums(
                    type: type,
                    size: 5,
                    fromYear: type.requiresYearRange ? 1900 : nil,
                    toYear: type.requiresYearRange ? 2100 : nil
                )
                albums[type.rawValue] = result.count
                parts.append("\(type.rawValue)=\(result.count)")
                if sampleAlbum == nil { sampleAlbum = result.first }
            }
            return parts.joined(separator: " ")
        }

        await step("getGenres") {
            let genres = try await client.genres()
            let preview = genres.prefix(5).map(\.name).joined(separator: ", ")
            return "\(genres.count): \(preview)"
        }

        print("\ncontent")
        await step("getAlbum") {
            guard let album = sampleAlbum else {
                throw HarnessError("library has no albums to read")
            }
            let detail = try await client.album(id: album.id)
            songs = detail.songs
            try require(!detail.songs.isEmpty, "album \(album.name) returned no songs")
            return "\(album.name): \(detail.songs.count) song(s)"
        }

        await step("getSongsByGenre") {
            let genre = try await client.genres().first?.name
            let result = try await client.songs(genre: genre, size: 20)
            return "genre=\(genre ?? "none") -> \(result.count) song(s)"
        }

        await step("search3") {
            let query = index.flatMap(\.artists).first?.name ?? sampleAlbum?.name ?? "a"
            let results = try await client.search(query: query, artistCount: 3, albumCount: 3, songCount: 5)
            subject = results.songs.first ?? songs.first
            return "query=\(query): \(results.artists.count) artist(s), "
                + "\(results.albums.count) album(s), \(results.songs.count) song(s)"
        }

        print("\nplaylists")
        await step("getPlaylists") {
            let playlists = try await client.playlists()
            let preview = playlists.prefix(5)
                .map { "\($0.name) (\($0.songCount ?? 0))" }
                .joined(separator: ", ")
            return "\(playlists.count): \(preview)"
        }

        await step("createPlaylist") {
            let id = try await client.createPlaylist(name: "navi-integration-check")
            try require(!id.isEmpty, "createPlaylist returned an empty id")
            playlistID = id
            return "id=\(id)"
        }

        await step("getPlaylist includes entries") {
            guard let id = playlistID else { throw HarnessError("no playlist id") }
            let detail = try await client.playlist(id: id)
            try require(detail.playlist.name == "navi-integration-check",
                        "unexpected name \(detail.playlist.name)")
            return "\(detail.playlist.name): \(detail.songs.count) song(s)"
        }

        await step("updatePlaylist") {
            guard let id = playlistID else { throw HarnessError("no playlist id") }
            guard let song = subject ?? songs.first else { throw HarnessError("nothing to add") }
            try await client.updatePlaylist(
                playlistID: id,
                name: "navi-integration-check",
                songIDsToAdd: [song.id]
            )
            let detail = try await client.playlist(id: id)
            try require(!detail.songs.isEmpty, "playlist still empty after update")
            return "\(detail.songs.count) entry(ies)"
        }

        await step("deletePlaylist") {
            guard let id = playlistID else { throw HarnessError("no playlist id") }
            try await client.deletePlaylist(id: id)
            playlistID = nil
            let playlists = try await client.playlists()
            try require(!playlists.contains { $0.id == id }, "playlist still present after delete")
            return "removed"
        }

        print("\nlyrics")
        await step("getLyrics") {
            // Lyrics are per-track, so gather candidates from real albums and
            // walk them until one is found rather than reporting "no lyrics" for
            // whichever single track happened to be picked.
            var candidates: [Song] = []
            for album in try await client.albums(type: .newest, size: 6) {
                candidates += (try await client.album(id: album.id)).songs
                if candidates.count >= 40 { break }
            }

            try require(!candidates.isEmpty, "no songs to look up lyrics for")

            var scanned = 0
            var found: (song: Song, lyrics: Lyrics)?

            for song in candidates.prefix(40) where found == nil {
                scanned += 1
                let lyrics = try await client.lyrics(songID: song.id)
                if !lyrics.lines.isEmpty { found = (song, lyrics) }
            }

            guard let found else {
                return "scanned \(scanned) track(s), none have lyrics on this server"
            }

            let lyrics = found.lyrics
            let kind = lyrics.isSynced ? "synced" : "unsynced"
            let wordTimed = lyrics.lines.filter(\.isWordTimed).count
            let first = lyrics.lines.first?.text ?? ""
            return "after \(scanned) track(s): \(kind), \(lyrics.lines.count) line(s), "
                + "\(wordTimed) word-timed, first=\"\(first.prefix(40))\""
        }

        print("\nartwork")
        await step("getCoverArt") {
            guard let id = sampleAlbum?.coverArtID ?? songs.first?.coverArtID else {
                throw HarnessError("no cover art id available")
            }
            guard let url = client.coverArtURL(id: id, size: 300) else {
                throw HarnessError("no cover art url")
            }
            let result = try await fetch(url)
            try require(result.bytes > 0, "empty cover art response")
            return "\(result.bytes) bytes, \(result.type ?? "unknown"), \(sanitised(url))"
        }

        print("\nstreaming")
        await step("stream at original quality") {
            guard let song = subject ?? songs.first else { throw HarnessError("no song") }
            guard let url = client.streamURL(for: song, quality: .original) else {
                throw HarnessError("no stream url")
            }
            let result = try await fetch(url)
            try require(result.bytes > 0, "empty stream")
            return "suffix=\(song.suffix ?? "?") -> \(result.bytes) bytes, "
                + "\(result.type ?? "unknown"), \(sanitised(url))"
        }

        for quality in [AudioQuality.high, .medium, .low] {
            await step("stream transcoded to \(quality.rawValue)") {
                guard let song = subject ?? songs.first else { throw HarnessError("no song") }
                guard let url = client.streamURL(for: song, quality: quality) else {
                    throw HarnessError("no stream url")
                }
                let result = try await fetch(url)
                try require(result.bytes > 0, "empty stream")
                return "\(result.bytes) bytes, \(result.type ?? "unknown"), \(sanitised(url))"
            }
        }

        await step("download original file") {
            guard let song = subject ?? songs.first else { throw HarnessError("no song") }
            guard let url = client.downloadURL(for: song) else {
                throw HarnessError("no download url")
            }
            let result = try await fetch(url)
            try require(result.bytes > 0, "empty download")
            return "\(result.bytes) bytes, \(result.type ?? "unknown")"
        }

        print("\nscrobbling")
        await step("scrobble") {
            guard let song = subject ?? songs.first else { throw HarnessError("no song") }
            try await client.scrobble(songs: [song], submission: false)
            return "now playing submitted"
        }

        await step("star / unstar") {
            guard let song = subject ?? songs.first else { throw HarnessError("no song") }
            try await client.setFavourite(songID: song.id, favourite: true)
            try await client.setFavourite(songID: song.id, favourite: false)
            return "toggled \(song.id)"
        }

        print("\n\(performed - failures.count)/\(performed) checks passed")
    }
}
