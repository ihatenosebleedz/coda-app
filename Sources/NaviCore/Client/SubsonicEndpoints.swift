import Foundation

public enum AlbumListType: String, Sendable, Hashable, CaseIterable, Identifiable {
    case alphabeticalByName
    case alphabeticalByArtist
    case recentlyAdded
    case newest
    case mostPlayed
    case highest
    case starred
    case random
    case byYear

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .alphabeticalByName: return "A-Z"
        case .alphabeticalByArtist: return "Artist"
        case .recentlyAdded: return "Recently Added"
        case .newest: return "Newest"
        case .mostPlayed: return "Most Played"
        case .highest: return "Top Rated"
        case .starred: return "Favourites"
        case .random: return "Random"
        case .byYear: return "By Year"
        }
    }

    /// Navidrome rejects `frequent`, `recent` and `byYear` on `getAlbumList2`, so
    /// those are requested through the legacy `getAlbumList` endpoint instead.
    var legacyWireValue: String? {
        switch self {
        case .recentlyAdded: return "recent"
        case .mostPlayed: return "frequent"
        case .byYear: return "byYear"
        default: return nil
        }
    }

    var method: String { legacyWireValue == nil ? "getAlbumList2" : "getAlbumList" }

    var wireValue: String { legacyWireValue ?? rawValue }

    /// Only `requiresYearRange` is part of the public API: callers that build
    /// the query themselves have to honour it, whereas `wireValue`,
    /// `legacyWireValue` and `method` are request-shaping internals.
    public var requiresYearRange: Bool { self == .byYear }
}

public struct ServerInfo: Sendable, Hashable {
    public var apiVersion: String
    public var serverType: String?
    public var serverVersion: String?
    public var supportsOpenSubsonic: Bool

    public init(apiVersion: String, serverType: String?, serverVersion: String?, supportsOpenSubsonic: Bool) {
        self.apiVersion = apiVersion
        self.serverType = serverType
        self.serverVersion = serverVersion
        self.supportsOpenSubsonic = supportsOpenSubsonic
    }
}

public struct ArtistIndex: Sendable, Hashable, Identifiable {
    public var letter: String
    public var artists: [Artist]

    public var id: String { letter }

    public init(letter: String, artists: [Artist]) {
        self.letter = letter
        self.artists = artists
    }
}

public struct AlbumDetail: Sendable, Hashable {
    public var album: Album
    public var songs: [Song]
}

public struct SearchResults: Sendable, Hashable {
    public var artists: [Artist]
    public var albums: [Album]
    public var songs: [Song]
}

extension SubsonicClient {

    public func ping() async throws -> ServerInfo {
        struct Response: Decodable {
            let version: String?
            let type: String?
            let serverVersion: String?
            let openSubsonic: Bool?
        }
        let payload: Response = try await perform("ping")
        return ServerInfo(
            apiVersion: payload.version ?? configuration.apiVersion,
            serverType: payload.type,
            serverVersion: payload.serverVersion,
            supportsOpenSubsonic: payload.openSubsonic ?? false
        )
    }

    public func musicFolders() async throws -> [MusicFolder] {
        struct Response: Decodable {
            let musicFolder: [MusicFolder]?
        }
        let payload: Response = try await perform("getMusicFolders")
        return payload.musicFolder ?? []
    }

    public func artistIndex(musicFolderID: Int? = nil) async throws -> [ArtistIndex] {
        struct Entry: Decodable {
            let name: String
            let artist: [Artist]?
        }
        struct Response: Decodable {
            let index: [Entry]?
            let child: [Entry]?
        }

        var parameters: [String: String] = [:]
        if let musicFolderID { parameters["musicFolderId"] = String(musicFolderID) }

        let payload: Response = try await perform("getIndexes", parameters)

        let entries = payload.index ?? payload.child ?? []
        return entries.map { ArtistIndex(letter: $0.name, artists: $0.artist ?? []) }
    }

    public func albums(
        type: AlbumListType,
        size: Int = 50,
        offset: Int = 0,
        genre: String? = nil,
        fromYear: Int? = nil,
        toYear: Int? = nil,
        musicFolderID: Int? = nil
    ) async throws -> [Album] {
        struct Response: Decodable {
            let album: [Album]?
        }

        if type.requiresYearRange, fromYear == nil || toYear == nil {
            throw ClientError.invalidRequest("\(type.label) needs a from and to year")
        }

        var parameters: [String: String] = [
            "type": type.wireValue,
            "size": String(size),
            "offset": String(offset)
        ]
        if let genre { parameters["genre"] = genre }
        if let fromYear { parameters["fromYear"] = String(fromYear) }
        if let toYear { parameters["toYear"] = String(toYear) }
        if let musicFolderID { parameters["musicFolderId"] = String(musicFolderID) }

        let payload: Response = try await perform(type.method, parameters)
        return payload.album ?? []
    }

    public func album(id: String) async throws -> AlbumDetail {
        let container: AlbumContainer = try await perform("getAlbum", ["id": id])
        return AlbumDetail(album: container.album, songs: container.song ?? [])
    }

    /// Navidrome's `getSongsByGenre` ignores `artistId` and `albumId`, so only the
/// filters the endpoint actually honours are exposed. Use `album(id:)` and
/// `topSongs(artistID:)` for album- and artist-scoped songs.
public func songs(
        genre: String? = nil,
        fromYear: Int? = nil,
        toYear: Int? = nil,
        offset: Int = 0,
        size: Int = 500,
        musicFolderID: Int? = nil
    ) async throws -> [Song] {
        struct Response: Decodable {
            let song: [Song]?
        }

        var parameters: [String: String] = [
            "offset": String(offset),
            "size": String(size)
        ]
        if let genre { parameters["genre"] = genre }
        if let fromYear { parameters["fromYear"] = String(fromYear) }
        if let toYear { parameters["toYear"] = String(toYear) }
        if let musicFolderID { parameters["musicFolderId"] = String(musicFolderID) }

        let payload: Response = try await perform("getSongsByGenre", parameters)
        return payload.song ?? []
    }

    public func randomSongs(
        size: Int = 50,
        genre: String? = nil,
        fromYear: Int? = nil,
        toYear: Int? = nil,
        musicFolderID: Int? = nil
    ) async throws -> [Song] {
        struct Response: Decodable {
            let song: [Song]?
        }

        var parameters: [String: String] = ["size": String(size)]
        if let genre { parameters["genre"] = genre }
        if let fromYear { parameters["fromYear"] = String(fromYear) }
        if let toYear { parameters["toYear"] = String(toYear) }
        if let musicFolderID { parameters["musicFolderId"] = String(musicFolderID) }

        let payload: Response = try await perform("getRandomSongs", parameters)
        return payload.song ?? []
    }

    public func search(
        query: String,
        artistCount: Int = 20,
        albumCount: Int = 20,
        songCount: Int = 40
    ) async throws -> SearchResults {
        struct Response: Decodable {
            let artist: [Artist]?
            let album: [Album]?
            let song: [Song]?
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchResults(artists: [], albums: [], songs: [])
        }

        let parameters: [String: String] = [
            "query": trimmed,
            "artistCount": String(artistCount),
            "artistOffset": "0",
            "albumCount": String(albumCount),
            "albumOffset": "0",
            "songCount": String(songCount),
            "songOffset": "0"
        ]

        let payload: Response = try await perform("search3", parameters)
        return SearchResults(
            artists: payload.artist ?? [],
            albums: payload.album ?? [],
            songs: payload.song ?? []
        )
    }

    public func topSongs(artistID: String, count: Int = 50) async throws -> [Song] {
        struct Response: Decodable {
            let song: [Song]?
        }
        let payload: Response = try await perform("getTopSongs", ["artist": artistID, "count": String(count)])
        return payload.song ?? []
    }

    public func genres() async throws -> [Genre] {
        struct Response: Decodable {
            let genre: [Genre]?
        }
        let payload: Response = try await perform("getGenres")
        return payload.genre ?? []
    }

    public func playlists() async throws -> [Playlist] {
        struct Response: Decodable {
            let playlist: [Playlist]?
        }
        let payload: Response = try await perform("getPlaylists")
        return payload.playlist ?? []
    }

    public func playlist(id: String) async throws -> (playlist: Playlist, songs: [Song]) {
        let container: PlaylistContainer = try await perform("getPlaylist", ["id": id])
        return (container.playlist, container.entry ?? [])
    }

    @discardableResult
    public func createPlaylist(name: String, songIDs: [String] = []) async throws -> String {
        var parameters: [String: String] = ["name": name]
        if !songIDs.isEmpty {
            parameters["songId"] = songIDs.joined(separator: ",")
        }
        let container: PlaylistContainer = try await perform("createPlaylist", parameters)
        return container.playlist.id
    }

    public func updatePlaylist(
        playlistID: String,
        name: String? = nil,
        comment: String? = nil,
        songIDsToAdd: [String] = [],
        songIndexesToRemove: [Int] = []
    ) async throws {
        struct Response: Decodable {
            let status: String?
        }
        var parameters: [String: String] = ["playlistId": playlistID]
        if let name { parameters["name"] = name }
        if let comment { parameters["comment"] = comment }
        if !songIDsToAdd.isEmpty {
            parameters["songIdToAdd"] = songIDsToAdd.joined(separator: ",")
        }
        if !songIndexesToRemove.isEmpty {
            parameters["songIndexToRemove"] = songIndexesToRemove
                .map(String.init)
                .joined(separator: ",")
        }
        let _: Response = try await perform("updatePlaylist", parameters)
    }

    public func deletePlaylist(id: String) async throws {
        struct Response: Decodable {
            let status: String?
        }
        let _: Response = try await perform("deletePlaylist", ["id": id])
    }

    public func setFavourite(
        songID: String? = nil,
        albumID: String? = nil,
        artistID: String? = nil,
        favourite: Bool
    ) async throws {
        struct Response: Decodable {
            let status: String?
        }
        var parameters: [String: String] = [:]
        if let songID { parameters["id"] = songID }
        if let albumID { parameters["albumId"] = albumID }
        if let artistID { parameters["artistId"] = artistID }

        let method = favourite ? "star" : "unstar"
        let _: Response = try await perform(method, parameters)
    }

    public func setRating(id: String, rating: Int) async throws {
        struct Response: Decodable {
            let status: String?
        }
        let _: Response = try await perform(
            "setRating",
            ["id": id, "rating": String(max(0, min(5, rating)))]
        )
    }

    public func nowPlaying(song: Song) async throws {
        struct Response: Decodable {
            let status: String?
        }
        let _: Response = try await perform(
            "nowPlaying",
            ["id": song.id, "time": String(Int(Date().timeIntervalSince1970 * 1000))]
        )
    }

    public func scrobble(songs: [Song], submission: Bool) async throws {
        guard !songs.isEmpty else { return }

        struct Response: Decodable {
            let status: String?
        }

        let now = Int(Date().timeIntervalSince1970 * 1000)
        let times = songs.map { _ in String(now) }.joined(separator: ",")
        let ids = songs.map(\.id).joined(separator: ",")

        var parameters: [String: String] = [
            "id": ids,
            "time": times,
            "submission": submission ? "true" : "false"
        ]
        if songs.count == 1, let rating = songs[0].userRating, rating > 0 {
            parameters["rating"] = String(rating)
        }

        let _: Response = try await perform("scrobble", parameters)
    }
}

/// `getAlbum` returns the album's own fields with `song` alongside them, so the
/// `album` wrapper key does not appear a second time inside the payload.
struct AlbumContainer: Decodable {
    let album: Album
    let song: [Song]?

    private enum Keys: String, CodingKey { case song }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        album = try Album(from: decoder)
        song = try container.decodeIfPresent([Song].self, forKey: .song)
    }
}

/// `getPlaylist` and `createPlaylist` both return a `playlist` object whose
/// playlist fields sit alongside its `entry` array.
struct PlaylistContainer: Decodable {
    let playlist: Playlist
    let entry: [Song]?

    private enum Keys: String, CodingKey { case entry }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        playlist = try Playlist(from: decoder)
        entry = try container.decodeIfPresent([Song].self, forKey: .entry)
    }
}