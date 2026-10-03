import Foundation

public struct Artist: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var albumCount: Int?
    public var coverArtID: String?
    public var starred: Date?

    public init(
        id: String,
        name: String,
        albumCount: Int? = nil,
        coverArtID: String? = nil,
        starred: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.coverArtID = coverArtID
        self.starred = starred
    }

    public var displaySubtitle: String? {
        guard let albumCount else { return nil }
        return "\(albumCount) album\(albumCount == 1 ? "" : "s")"
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case albumCount
        case coverArtID = "coverArt"
        case starred
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        albumCount = try c.decodeIfPresent(Int.self, forKey: .albumCount)
        coverArtID = try c.decodeIfPresent(String.self, forKey: .coverArtID)
        starred = try c.decodeIfPresent(Date.self, forKey: .starred)
    }
}

public struct Album: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var artistID: String?
    public var artistName: String?
    public var songCount: Int?
    public var duration: Int?
    public var year: Int?
    public var genre: String?
    public var coverArtID: String?
    public var created: Date?
    public var starred: Date?
    public var played: Date?
    public var userRating: Int?
    public var isCompilation: Bool

    public init(
        id: String,
        name: String,
        artistID: String? = nil,
        artistName: String? = nil,
        songCount: Int? = nil,
        duration: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        coverArtID: String? = nil,
        created: Date? = nil,
        starred: Date? = nil,
        played: Date? = nil,
        userRating: Int? = nil,
        isCompilation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.artistID = artistID
        self.artistName = artistName
        self.songCount = songCount
        self.duration = duration
        self.year = year
        self.genre = genre
        self.coverArtID = coverArtID
        self.created = created
        self.starred = starred
        self.played = played
        self.userRating = userRating
        self.isCompilation = isCompilation
    }

    public var displayArtist: String {
        if let artistName, !artistName.isEmpty { return artistName }
        return "Unknown Artist"
    }

    public var displaySubtitle: String {
        var parts: [String] = [displayArtist]
        if let year { parts.append(String(year)) }
        if let songCount { parts.append("\(songCount) song\(songCount == 1 ? "" : "s")") }
        return parts.joined(separator: " • ")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, year, genre, duration, created, starred, played
        case artistID = "artistId"
        case artistName = "artist"
        case songCount
        case coverArtID = "coverArt"
        case userRating
        case isCompilation
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        artistID = try c.decodeIfPresent(String.self, forKey: .artistID)
        artistName = try c.decodeIfPresent(String.self, forKey: .artistName)
        songCount = try c.decodeIfPresent(Int.self, forKey: .songCount)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        coverArtID = try c.decodeIfPresent(String.self, forKey: .coverArtID)
        created = try c.decodeIfPresent(Date.self, forKey: .created)
        starred = try c.decodeIfPresent(Date.self, forKey: .starred)
        played = try c.decodeIfPresent(Date.self, forKey: .played)
        userRating = try c.decodeIfPresent(Int.self, forKey: .userRating)
        isCompilation = try c.decodeIfPresent(Bool.self, forKey: .isCompilation) ?? false
    }
}

public struct Song: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var parentID: String?
    public var title: String
    public var album: String?
    public var albumID: String?
    public var artist: String?
    public var artistID: String?
    public var track: Int?
    public var discNumber: Int?
    public var year: Int?
    public var genre: String?
    public var coverArtID: String?
    public var size: Int?
    public var contentType: String?
    public var suffix: String?
    public var transcodedContentType: String?
    public var transcodedSuffix: String?
    public var duration: Int?
    public var bitRate: Int?
    public var path: String?
    public var isVideo: Bool
    public var created: Date?
    public var played: Date?
    public var starred: Date?
    public var userRating: Int?

    public init(
        id: String,
        title: String,
        parentID: String? = nil,
        album: String? = nil,
        albumID: String? = nil,
        artist: String? = nil,
        artistID: String? = nil,
        track: Int? = nil,
        discNumber: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        coverArtID: String? = nil,
        size: Int? = nil,
        contentType: String? = nil,
        suffix: String? = nil,
        transcodedContentType: String? = nil,
        transcodedSuffix: String? = nil,
        duration: Int? = nil,
        bitRate: Int? = nil,
        path: String? = nil,
        isVideo: Bool = false,
        created: Date? = nil,
        played: Date? = nil,
        starred: Date? = nil,
        userRating: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.parentID = parentID
        self.album = album
        self.albumID = albumID
        self.artist = artist
        self.artistID = artistID
        self.track = track
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.coverArtID = coverArtID
        self.size = size
        self.contentType = contentType
        self.suffix = suffix
        self.transcodedContentType = transcodedContentType
        self.transcodedSuffix = transcodedSuffix
        self.duration = duration
        self.bitRate = bitRate
        self.path = path
        self.isVideo = isVideo
        self.created = created
        self.played = played
        self.starred = starred
        self.userRating = userRating
    }

    public var displayArtist: String {
        if let artist, !artist.isEmpty { return artist }
        return "Unknown Artist"
    }

    public var displayAlbum: String {
        if let album, !album.isEmpty { return album }
        return "Unknown Album"
    }

    public var isFavourite: Bool { starred != nil }

    enum CodingKeys: String, CodingKey {
        case id, title, album, artist, track, year, genre, size, suffix
        case duration, path, created, played, starred, userRating, isVideo
        case parentID = "parent"
        case albumID = "albumId"
        case artistID = "artistId"
        case discNumber
        case coverArtID = "coverArt"
        case contentType
        case transcodedContentType
        case transcodedSuffix
        case bitRate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        albumID = try c.decodeIfPresent(String.self, forKey: .albumID)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        artistID = try c.decodeIfPresent(String.self, forKey: .artistID)
        track = try c.decodeIfPresent(Int.self, forKey: .track)
        discNumber = try c.decodeIfPresent(Int.self, forKey: .discNumber)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        coverArtID = try c.decodeIfPresent(String.self, forKey: .coverArtID)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        suffix = try c.decodeIfPresent(String.self, forKey: .suffix)
        transcodedContentType = try c.decodeIfPresent(String.self, forKey: .transcodedContentType)
        transcodedSuffix = try c.decodeIfPresent(String.self, forKey: .transcodedSuffix)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        bitRate = try c.decodeIfPresent(Int.self, forKey: .bitRate)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        isVideo = try c.decodeIfPresent(Bool.self, forKey: .isVideo) ?? false
        created = try c.decodeIfPresent(Date.self, forKey: .created)
        played = try c.decodeIfPresent(Date.self, forKey: .played)
        starred = try c.decodeIfPresent(Date.self, forKey: .starred)
        userRating = try c.decodeIfPresent(Int.self, forKey: .userRating)
    }
}

public struct Playlist: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var comment: String?
    public var owner: String?
    public var isPublic: Bool
    public var songCount: Int?
    public var duration: Int?
    public var created: Date?
    public var changed: Date?
    public var coverArtID: String?

    public init(
        id: String,
        name: String,
        comment: String? = nil,
        owner: String? = nil,
        isPublic: Bool = false,
        songCount: Int? = nil,
        duration: Int? = nil,
        created: Date? = nil,
        changed: Date? = nil,
        coverArtID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.isPublic = isPublic
        self.songCount = songCount
        self.duration = duration
        self.created = created
        self.changed = changed
        self.coverArtID = coverArtID
    }

    enum CodingKeys: String, CodingKey {
        case id, name, comment, owner, duration, created, changed
        case isPublic = "public"
        case songCount
        case coverArtID = "coverArt"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        songCount = try c.decodeIfPresent(Int.self, forKey: .songCount)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        created = try c.decodeIfPresent(Date.self, forKey: .created)
        changed = try c.decodeIfPresent(Date.self, forKey: .changed)
        coverArtID = try c.decodeIfPresent(String.self, forKey: .coverArtID)
    }
}

public struct Genre: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var songCount: Int?
    public var albumCount: Int?

    public var id: String { name }

    public init(name: String, songCount: Int? = nil, albumCount: Int? = nil) {
        self.name = name
        self.songCount = songCount
        self.albumCount = albumCount
    }

    enum CodingKeys: String, CodingKey {
        case songCount, albumCount
        case name = "value"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        songCount = try c.decodeIfPresent(Int.self, forKey: .songCount)
        albumCount = try c.decodeIfPresent(Int.self, forKey: .albumCount)
    }
}

public struct MusicFolder: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}