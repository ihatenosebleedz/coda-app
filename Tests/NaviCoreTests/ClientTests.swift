import XCTest
@testable import NaviCore

final class ClientTests: XCTestCase {

    private func makeClient(
        transport: StubTransport,
        user: String = "alice",
        password: String = "hunter2"
    ) -> SubsonicClient {
        SubsonicClient(
            configuration: ServerConfiguration(
                baseURL: URL(string: "https://music.example.com")!,
                username: user,
                password: password
            ),
            transport: transport,
            saltProvider: { "abc123" }
        )
    }

    private func queryItems(_ url: URL?) -> [String: String] {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        return Dictionary(items.compactMap { item in
            item.value.map { (item.name, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    func testURLTargetsRestPathAndCarriesRequiredParams() {
        let client = makeClient(transport: StubTransport.json(Fixture.ok()))
        let url = client.url(for: "ping")

        XCTAssertEqual(url?.absoluteString.hasPrefix("https://music.example.com/rest/ping?"), true)

        let items = queryItems(url)
        XCTAssertEqual(items["v"], "1.16.1")
        XCTAssertEqual(items["f"], "json")
        XCTAssertEqual(items["c"], "Navi")
        XCTAssertEqual(items["u"], "alice")
        XCTAssertEqual(items["s"], "abc123")
        XCTAssertEqual(items["t"], MD5.hex("hunter2abc123"))
    }

    func testBaseURLWithTrailingSlashDoesNotDoubleUp() {
        let configuration = ServerConfiguration(
            baseURL: URL(string: "https://music.example.com/")!,
            username: "a",
            password: "b"
        )
        let client = SubsonicClient(configuration: configuration, transport: StubTransport.json(Fixture.ok()))
        XCTAssertEqual(
            client.url(for: "ping")?.absoluteString.hasPrefix("https://music.example.com/rest/ping?"),
            true
        )
    }

    func testServerURLNormalisation() {
        XCTAssertEqual(
            ServerConfiguration.normalise(urlString: "music.example.com")?.absoluteString,
            "https://music.example.com"
        )
        XCTAssertEqual(
            ServerConfiguration.normalise(urlString: "  http://192.168.1.10:4533/  ")?.absoluteString,
            "http://192.168.1.10:4533"
        )
        XCTAssertEqual(
            ServerConfiguration.normalise(urlString: "https://music.example.com/navidrome")?.absoluteString,
            "https://music.example.com/navidrome"
        )
        XCTAssertNil(ServerConfiguration.normalise(urlString: "   "))
    }

    func testAuthenticationFailureSurfacesSubsonicErrorCode() async {
        let client = makeClient(
            transport: StubTransport.json(Fixture.failure(code: 40, message: "Wrong username or password."))
        )

        do {
            _ = try await client.ping()
            XCTFail("expected authentication failure")
        } catch let error as ClientError {
            guard case .subsonic(let subsonicError) = error else {
                return XCTFail("expected subsonic error, got \(error)")
            }
            XCTAssertEqual(subsonicError.code, 40)
            XCTAssertTrue(subsonicError.isAuthenticationFailure)
            XCTAssertEqual(subsonicError.description, "Wrong username or password")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testNonOKHTTPStatusBecomesUnreachable() async {
        let client = makeClient(transport: StubTransport.json(Fixture.ok(), statusCode: 502))

        do {
            _ = try await client.ping()
            XCTFail("expected failure")
        } catch let error as ClientError {
            guard case .unreachable(let message) = error else {
                return XCTFail("expected unreachable, got \(error)")
            }
            XCTAssertTrue(message.contains("502"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTransportErrorBecomesTransportError() async {
        let client = makeClient(transport: StubTransport.failing(.transport("connection reset")))

        do {
            _ = try await client.ping()
            XCTFail("expected failure")
        } catch let error as ClientError {
            XCTAssertEqual(error, .transport("connection reset"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMalformedPayloadBecomesDecodingError() async {
        let wrongPayloadType = makeClient(
            transport: StubTransport.json(Fixture.envelope("\"albumList2\":\"nope\""))
        )
        let wrongInnerType = makeClient(
            transport: StubTransport.json(Fixture.envelope("\"albumList2\":{\"album\":{\"not\":\"array\"}}"))
        )

        for client in [wrongPayloadType, wrongInnerType] {
            do {
                _ = try await client.albums(type: .newest)
                XCTFail("expected decoding failure")
            } catch let error as ClientError {
                guard case .decoding = error else {
                    return XCTFail("expected decoding error, got \(error)")
                }
            } catch {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    func testPingReportsOpenSubsonicSupport() async throws {
        let client = makeClient(transport: StubTransport.json(Fixture.ok()))
        let info = try await client.ping()

        XCTAssertEqual(info.apiVersion, "1.16.1")
        XCTAssertEqual(info.serverType, "Navidrome")
        XCTAssertEqual(info.serverVersion, "0.58.0")
        XCTAssertTrue(info.supportsOpenSubsonic)
    }

    func testAlbumDecodingHandlesNanosecondTimestamps() async throws {
        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(Fixture.albumJSON()))
        )

        let albums = try await client.albums(type: .alphabeticalByName, size: 25, offset: 50)

        XCTAssertEqual(albums.count, 1)
        let album = try XCTUnwrap(albums.first)
        XCTAssertEqual(album.id, "al-1")
        XCTAssertEqual(album.name, "Kid A")
        XCTAssertEqual(album.displayArtist, "Radiohead")
        XCTAssertEqual(album.songCount, 10)
        XCTAssertEqual(album.year, 2000)
        XCTAssertEqual(album.coverArtID, "cover-al-1")

        let created = try XCTUnwrap(album.created)
        XCTAssertEqual(Int(created.timeIntervalSince1970), 970444800)
    }

    func testAlbumListParametersAreSentCorrectly() async throws {
        let recorder = RequestRecorder()
        let transport = StubTransport { request in
            recorder.record(request)
            return (Data(Fixture.envelope("\"albumList2\":{\"album\":[]}").utf8), HTTPResponse(statusCode: 200))
        }
        let client = makeClient(transport: transport)

        _ = try await client.albums(
            type: .starred,
            size: 30,
            offset: 60,
            genre: "Shoegaze",
            fromYear: 1990,
            toYear: 1999
        )

        let request = try XCTUnwrap(recorder.requests.first)
        let items = queryItems(request.url)

        XCTAssertEqual(request.url.path, "/rest/getAlbumList2")
        XCTAssertEqual(items["type"], "starred")
        XCTAssertEqual(items["size"], "30")
        XCTAssertEqual(items["offset"], "60")
        XCTAssertEqual(items["genre"], "Shoegaze")
        XCTAssertEqual(items["fromYear"], "1990")
        XCTAssertEqual(items["toYear"], "1999")
    }

    func testMissingArrayKeysDecodeToEmptyRatherThanFailing() async throws {
        let client = makeClient(transport: StubTransport.json(Fixture.envelope("\"albumList2\":{}")))

        let albums = try await client.albums(type: .newest)
        XCTAssertTrue(albums.isEmpty)
    }

    func testSearchTrimsBlankQueryAndSkipsRequest() async throws {
        let recorder = RequestRecorder()
        let transport = StubTransport { request in
            recorder.record(request)
            return (Data(Fixture.envelope("\"searchResult3\":{}").utf8), HTTPResponse(statusCode: 200))
        }
        let client = makeClient(transport: transport)

        let results = try await client.search(query: "   ")

        XCTAssertTrue(results.artists.isEmpty)
        XCTAssertTrue(results.albums.isEmpty)
        XCTAssertTrue(results.songs.isEmpty)
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testCoverArtURLIncludesSize() {
        let client = makeClient(transport: StubTransport.json(Fixture.ok()))
        let items = queryItems(client.coverArtURL(id: "cover-1", size: 300))

        XCTAssertEqual(items["id"], "cover-1")
        XCTAssertEqual(items["size"], "300")
    }

    func testResponseKeysMatchSubsonicEnvelopeNames() {
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getAlbumList2"), "albumList2")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getAlbumList"), "albumList")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getAlbum"), "album")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getMusicFolders"), "musicFolders")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getIndexes"), "indexes")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getSongsByGenre"), "songsByGenre")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getRandomSongs"), "randomSongs")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getTopSongs"), "topSongs")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getGenres"), "genres")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getPlaylists"), "playlists")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getPlaylist"), "playlist")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "createPlaylist"), "playlist")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "getLyrics"), "lyrics")
        XCTAssertEqual(SubsonicClient.defaultResponseKey(for: "search3"), "searchResult3")

        XCTAssertNil(SubsonicClient.defaultResponseKey(for: "ping"))
        XCTAssertNil(SubsonicClient.defaultResponseKey(for: "star"))
        XCTAssertNil(SubsonicClient.defaultResponseKey(for: "unstar"))
        XCTAssertNil(SubsonicClient.defaultResponseKey(for: "scrobble"))
        XCTAssertNil(SubsonicClient.defaultResponseKey(for: "setRating"))
        XCTAssertNil(SubsonicClient.defaultResponseKey(for: "updatePlaylist"))
        XCTAssertNil(SubsonicClient.defaultResponseKey(for: "deletePlaylist"))
    }

    func testSearchDecodesFromSearchResult3Wrapper() async throws {
        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(Fixture.searchJSON()))
        )

        let results = try await client.search(query: "kid")

        XCTAssertEqual(results.artists.map(\.name), ["Radiohead"])
        XCTAssertEqual(results.albums.map(\.name), ["Kid A"])
        XCTAssertEqual(results.songs.map(\.id), ["s-1"])

        let song = try XCTUnwrap(results.songs.first)
        XCTAssertEqual(song.title, "Everything In Its Right Place")
        XCTAssertEqual(song.suffix, "flac")
        XCTAssertEqual(song.duration, 312)
        XCTAssertTrue(song.isDirectlyPlayableByAVPlayer)
    }

    func testPlaylistsDecodeFromPlaylistsWrapper() async throws {
        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(Fixture.playlistsJSON()))
        )

        let playlists = try await client.playlists()

        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists.first?.id, "pl-1")
        XCTAssertEqual(playlists.first?.name, "Chill")
        XCTAssertEqual(playlists.first?.comment, "mood")
        XCTAssertEqual(playlists.first?.owner, "admin")
        XCTAssertEqual(playlists.first?.songCount, 42)
        XCTAssertEqual(playlists.first?.isPublic, false)
    }

    func testPlaylistDetailIncludesEntries() async throws {
        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(Fixture.playlistJSON()))
        )

        let result = try await client.playlist(id: "pl-1")

        XCTAssertEqual(result.playlist.name, "Chill")
        XCTAssertEqual(result.songs.map(\.title), ["Track 0", "Track 1"])
    }

    func testMusicFoldersIndexesAndGenresDecode() async throws {
        let folders = makeClient(transport: StubTransport.json(Fixture.envelope(Fixture.musicFoldersJSON())))
        let indexes = makeClient(transport: StubTransport.json(Fixture.envelope(Fixture.indexesJSON())))
        let genres = makeClient(transport: StubTransport.json(Fixture.envelope(Fixture.genresJSON())))

        let foldersResult = try await folders.musicFolders()
        XCTAssertEqual(foldersResult, [MusicFolder(id: 1, name: "Music")])

        let indexResult = try await indexes.artistIndex()
        XCTAssertEqual(indexResult.count, 1)
        XCTAssertEqual(indexResult.first?.letter, "R")
        XCTAssertEqual(indexResult.first?.artists.map(\.name), ["Radiohead"])

        let genreResult = try await genres.genres()
        XCTAssertEqual(genreResult.first?.name, "Alternative")
        XCTAssertEqual(genreResult.first?.songCount, 10)
    }

    func testEmptyContainerResultsDecodeToEmptyArrays() async throws {
        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(
                "\"playlists\":{},\"genres\":{},\"musicFolders\":{},\"indexes\":{}"
            ))
        )

        let playlists = try await client.playlists()
        let genreList = try await client.genres()
        let folderList = try await client.musicFolders()
        let indexList = try await client.artistIndex()

        XCTAssertTrue(playlists.isEmpty)
        XCTAssertTrue(genreList.isEmpty)
        XCTAssertTrue(folderList.isEmpty)
        XCTAssertTrue(indexList.isEmpty)
    }

    func testPlainLyricsDecodeFromLyricsWrapper() async throws {
        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(Fixture.lyricsJSON()))
        )

        let lyrics = try await client.lyrics(songID: "s-1")

        XCTAssertEqual(lyrics.artist, "Radiohead")
        XCTAssertEqual(lyrics.title, "Everything In Its Right Place")
        XCTAssertEqual(lyrics.lines.map(\.text), ["Everything in its right place"])
    }

    func testStructuredLyricsKeepWordTimingsAndApplyOffset() async throws {        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(Fixture.structuredLyricsJSON()))
        )

        let lyrics = try await client.lyrics(songID: "s-1")

        XCTAssertEqual(lyrics.lines.count, 2)
        let first = try XCTUnwrap(lyrics.lines.first)
        XCTAssertEqual(first.start, 10, accuracy: 0.001)
        XCTAssertEqual(first.words.map(\.text), ["Everything", "in", "its", "right", "place"])
        XCTAssertEqual(first.words[1].start, 10.7, accuracy: 0.001)
        XCTAssertTrue(first.isWordTimed)

        XCTAssertEqual(lyrics.activeWordIndex(at: 10.8), 1)
        XCTAssertEqual(lyrics.activeLine(at: 15)?.text, "Nice dream")
    }

    func testAlbumDetailDecodesSongsAsSiblingsOfAlbumFields() async throws {
        let client = makeClient(
            transport: StubTransport.json(Fixture.envelope(Fixture.albumDetailJSON()))
        )

        let detail = try await client.album(id: "al-1")

        XCTAssertEqual(detail.album.id, "al-1")
        XCTAssertEqual(detail.album.name, "Kid A")
        XCTAssertEqual(detail.album.displayArtist, "Radiohead")
        XCTAssertEqual(detail.songs.map(\.id), ["s-0", "s-1"])
        XCTAssertEqual(detail.songs.map(\.title), ["Track 0", "Track 1"])
    }

    func testAlbumListTypesRouteThroughLegacyEndpointWhereRequired() {
        XCTAssertEqual(AlbumListType.alphabeticalByName.method, "getAlbumList2")
        XCTAssertEqual(AlbumListType.alphabeticalByName.wireValue, "alphabeticalByName")
        XCTAssertEqual(AlbumListType.starred.method, "getAlbumList2")
        XCTAssertEqual(AlbumListType.highest.method, "getAlbumList2")

        XCTAssertEqual(AlbumListType.recentlyAdded.method, "getAlbumList")
        XCTAssertEqual(AlbumListType.recentlyAdded.wireValue, "recent")
        XCTAssertEqual(AlbumListType.mostPlayed.method, "getAlbumList")
        XCTAssertEqual(AlbumListType.mostPlayed.wireValue, "frequent")
        XCTAssertEqual(AlbumListType.byYear.method, "getAlbumList")

        XCTAssertTrue(AlbumListType.byYear.requiresYearRange)
        XCTAssertFalse(AlbumListType.recentlyAdded.requiresYearRange)
    }

    func testByYearAlbumListRequiresAYearRange() async {
        let client = makeClient(transport: StubTransport.json(Fixture.ok()))

        do {
            _ = try await client.albums(type: .byYear)
            XCTFail("expected invalid request")
        } catch let error as ClientError {
            guard case .invalidRequest = error else {
                return XCTFail("expected invalidRequest, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRecentlyAddedUsesLegacyEndpointAndWireValue() async throws {
        let recorder = RequestRecorder()
        let transport = StubTransport { request in
            recorder.record(request)
            return (
                Data(Fixture.envelope("\"albumList\":{\"album\":[]}").utf8),
                HTTPResponse(statusCode: 200)
            )
        }
        let client = makeClient(transport: transport)

        _ = try await client.albums(type: .recentlyAdded, size: 10)

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url.path, "/rest/getAlbumList")
        XCTAssertEqual(queryItems(request.url)["type"], "recent")
        XCTAssertEqual(queryItems(request.url)["size"], "10")
    }
}