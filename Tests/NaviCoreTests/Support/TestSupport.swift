import Foundation
import XCTest
@testable import NaviCore

struct StubTransport: HTTPTransport {
    let handler: @Sendable (HTTPRequest) async throws -> (Data, HTTPResponse)

    init(handler: @escaping @Sendable (HTTPRequest) async throws -> (Data, HTTPResponse)) {
        self.handler = handler
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPResponse) {
        try await handler(request)
    }

    static func json(_ body: String, statusCode: Int = 200) -> StubTransport {
        StubTransport { _ in
            (Data(body.utf8), HTTPResponse(statusCode: statusCode))
        }
    }

    static func failing(_ error: ClientError) -> StubTransport {
        StubTransport { _ in throw error }
    }
}

final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HTTPRequest] = []

    var requests: [HTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ request: HTTPRequest) {
        lock.lock()
        storage.append(request)
        lock.unlock()
    }
}

enum Fixture {
    static func envelope(_ payload: String, status: String = "ok") -> String {
        let meta = "\"status\":\"\(status)\",\"version\":\"1.16.1\",\"type\":\"Navidrome\",\"serverVersion\":\"0.58.0\",\"openSubsonic\":true"
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty ? meta : "\(meta),\(trimmed)"
        return "{\"subsonic-response\":{\(body)}}"
    }

    static func ok() -> String { envelope("") }

    static func failure(code: Int, message: String) -> String {
        """
        {"subsonic-response":{"status":"failed","version":"1.16.1",\
        "error":{"code":\(code),"message":"\(message)"}}}
        """
    }

    static func makeSong(
        id: String,
        title: String = "Title",
        artist: String = "Artist",
        album: String = "Album",
        suffix: String? = "flac",
        duration: Int? = 210
    ) -> Song {
        Song(
            id: id,
            title: title,
            album: album,
            artist: artist,
            contentType: suffix == "flac" ? "audio/flac" : "audio/mpeg",
            suffix: suffix,
            duration: duration,
            bitRate: 900
        )
    }

    static func albumJSON(
        id: String = "al-1",
        name: String = "Kid A",
        artist: String = "Radiohead",
        created: String = "2000-10-02T00:00:00.000000000Z"
    ) -> String {
        let album = """
        {"id":"\(id)","name":"\(name)","artist":"\(artist)","artistId":"ar-1",\
        "coverArt":"cover-\(id)","songCount":10,"duration":3000,"year":2000,\
        "genre":"Alternative","created":"\(created)"}
        """
        return "\"albumList2\":{\"album\":[\(album)]}"
    }

    static func songJSON(id: String = "s-1", title: String = "Everything In Its Right Place") -> String {
        """
        {"id":"\(id)","title":"\(title)","album":"Amnesiac","albumId":"al-1",\
        "artist":"Radiohead","artistId":"ar-1","track":1,"discNumber":1,"year":2001,\
        "genre":"Alternative","coverArt":"cover-s-1","size":1234567,"contentType":"audio/flac",\
        "suffix":"flac","duration":312,"bitRate":900,"isVideo":false,\
        "created":"2001-06-18T00:00:00.000Z"}
        """
    }

    /// `getAlbum` returns the album's own fields with `song` alongside them.
static func albumDetailJSON(id: String = "al-1", name: String = "Kid A") -> String {
        let songs = (0..<2)
            .map { songJSON(id: "s-\($0)", title: "Track \($0)") }
            .joined(separator: ",")

        return """
        "album":{"id":"\(id)","name":"\(name)","artist":"Radiohead","artistId":"ar-1",\
        "coverArt":"cover-\(id)","songCount":2,"duration":600,"year":2000,"song":[\(songs)]}
        """
    }

    /// `search3` nests results under `searchResult3`.
    static func searchJSON(query: String = "kid") -> String {
        let artist = "{\"id\":\"ar-1\",\"name\":\"Radiohead\",\"albumCount\":9,\"coverArt\":\"cover-ar-1\"}"
        let album = "{\"id\":\"al-1\",\"name\":\"Kid A\",\"artist\":\"Radiohead\",\"songCount\":10}"
        return """
        "searchResult3":{"artist":[\(artist)],"album":[\(album)],"song":[\(songJSON())]}
        """
    }

    static func playlistsJSON() -> String {
        let playlist = """
        {"id":"pl-1","name":"Chill","comment":"mood","owner":"admin","public":false,\
        "songCount":42,"duration":7200,"created":"2024-01-01T00:00:00.000Z",\
        "changed":"2024-02-01T00:00:00.000Z"}
        """
        return "\"playlists\":{\"playlist\":[\(playlist)]}"
    }

    static func playlistJSON(id: String = "pl-1", name: String = "Chill", songCount: Int = 2) -> String {
        let entries = (0..<songCount)
            .map { songJSON(id: "s-\($0)", title: "Track \($0)") }
            .joined(separator: ",")

        return """
        "playlist":{"id":"\(id)","name":"\(name)","owner":"admin","public":false,\
        "songCount":\(songCount),"entry":[\(entries)]}
        """
    }

    static func musicFoldersJSON() -> String {
        "\"musicFolders\":{\"musicFolder\":[{\"id\":1,\"name\":\"Music\"}]}"
    }

    static func indexesJSON() -> String {
        let artist = "{\"id\":\"ar-1\",\"name\":\"Radiohead\",\"albumCount\":9}"
        return "\"indexes\":{\"index\":[{\"name\":\"R\",\"artist\":[\(artist)]}]}"
    }

    static func genresJSON() -> String {
        "\"genres\":{\"genre\":[{\"value\":\"Alternative\",\"songCount\":10,\"albumCount\":1}]}"
    }

    static func lyricsJSON(
        artist: String = "Radiohead",
        title: String = "Everything In Its Right Place",
        value: String = "[00:10.50]Everything in its right place"
    ) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"lyrics\":{\"artist\":\"\(artist)\",\"title\":\"\(title)\",\"value\":\"\(escaped)\"}"
    }

    static func structuredLyricsJSON() -> String {
        let lines = """
        {"startTime":10050,"value":"Everything in its right place","text":[
        {"value":"Everything","start":0,"duration":700},
        {"value":"in","start":700,"duration":400},
        {"value":"its","start":1100,"duration":450},
        {"value":"right","start":1550,"duration":550},
        {"value":"place","start":2100,"duration":600}]},
        {"startTime":15000,"duration":900,"value":"Nice dream"}
        """
        return "\"lyrics\":{\"artist\":\"Radiohead\",\"structuredLyrics\":{\"offset\":50,\"line\":[\(lines)]}}"
    }

    static func lyricFile(wordTimed: Bool = true) -> String {
        if wordTimed {
            return """
            [ar:Radiohead]
            [ti:Everything In Its Right Place]
            [al:Amnesiac]
            [offset:+200]
            [00:10.50]<00:10.50>Everything <00:11.20>in <00:11.60>its <00:12.05>right <00:12.60>place
            [00:15.00]<00:15.00>Nice <00:15.40>dream
            [00:20.00]Instrumental
            """
        }

        return """
        [ar:Radiohead]
        [00:10.50]Everything in its right place
        [00:15.00]Nice dream
        """
    }
}