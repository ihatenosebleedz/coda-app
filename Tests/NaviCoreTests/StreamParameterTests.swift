import XCTest
@testable import NaviCore

final class StreamParameterTests: XCTestCase {

    private let client = SubsonicClient(
        configuration: ServerConfiguration(
            baseURL: URL(string: "https://music.example.com")!,
            username: "a",
            password: "b"
        ),
        transport: StubTransport.json(Fixture.ok()),
        saltProvider: { "abc123" }
    )

    func testPlayableFormatStreamsRaw() {
        let song = Fixture.makeSong(id: "1", suffix: "flac")
        let params = client.streamParameters(for: song, quality: .original)

        XCTAssertEqual(params["format"], "raw")
        XCTAssertNil(params["maxBitRate"])
    }

    func testUnplayableFormatIsTranscodedEvenAtOriginalQuality() {
        for suffix in ["ogg", "opus", "wma", "ape", "wv"] {
            let song = Fixture.makeSong(id: "1", suffix: suffix)
            XCTAssertFalse(song.isDirectlyPlayableByAVPlayer, "\(suffix) should not be AVPlayer-playable")

            let params = client.streamParameters(for: song, quality: .original)
            XCTAssertEqual(params["format"], "mp3", "\(suffix) should transcode to mp3")
            XCTAssertEqual(params["maxBitRate"], "320", "\(suffix) should cap at 320k")
        }
    }

    func testPlayableSuffixDetection() {
        let playable = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac", "alac"]
        for suffix in playable {
            XCTAssertTrue(
                Fixture.makeSong(id: "1", suffix: suffix).isDirectlyPlayableByAVPlayer,
                "\(suffix) should be playable"
            )
        }

        let notPlayable = ["ogg", "opus", "wma", "mpc", "ape", "wv", "aiff2", "shn"]
        for suffix in notPlayable {
            XCTAssertFalse(
                Fixture.makeSong(id: "1", suffix: suffix).isDirectlyPlayableByAVPlayer,
                "\(suffix) should not be playable"
            )
        }
    }

    func testSuffixMatchingIsCaseInsensitive() {
        XCTAssertTrue(Fixture.makeSong(id: "1", suffix: "FLAC").isDirectlyPlayableByAVPlayer)
        XCTAssertTrue(Fixture.makeSong(id: "1", suffix: "MP3").isDirectlyPlayableByAVPlayer)
    }

    func testMissingSuffixIsTreatedAsUnplayable() {
        XCTAssertFalse(Fixture.makeSong(id: "1", suffix: nil).isDirectlyPlayableByAVPlayer)
    }

    func testQualityCapsProduceExpectedBitrates() {
        let flac = Fixture.makeSong(id: "1", suffix: "flac")

        XCTAssertEqual(client.streamParameters(for: flac, quality: .high)["maxBitRate"], "320")
        XCTAssertEqual(client.streamParameters(for: flac, quality: .medium)["maxBitRate"], "192")
        XCTAssertEqual(client.streamParameters(for: flac, quality: .low)["maxBitRate"], "96")
        XCTAssertEqual(client.streamParameters(for: flac, quality: .lossless)["maxBitRate"], "1411")
    }

    func testLosslessOnFlacUsesMp3ContainerNotRawFlac() {
        let flac = Fixture.makeSong(id: "1", suffix: "flac")
        XCTAssertEqual(client.streamParameters(for: flac, quality: .lossless)["format"], "mp3")

        let mp3 = Fixture.makeSong(id: "2", suffix: "mp3")
        XCTAssertEqual(client.streamParameters(for: mp3, quality: .lossless)["format"], "mp3")
    }

    func testStreamURLPathIsCorrect() {
        let song = Fixture.makeSong(id: "song-9")
        XCTAssertEqual(
            client.streamURL(for: song, quality: .high)?.path,
            "/rest/stream"
        )
    }

    func testTranscodedSuffixIsPreferredForFormatDecision() {
        let song = Fixture.makeSong(id: "1", suffix: "flac")
        var transcoded = song
        transcoded.transcodedSuffix = "mp3"

        XCTAssertEqual(transcoded.resolvedSuffix, "mp3")
    }

    func testAudioQualityRoundTripsThroughCodable() throws {
        // The app persists the selected quality in UserDefaults, which relies
        // on AudioQuality being Codable.
        for quality in AudioQuality.allCases {
            let data = try JSONEncoder().encode(quality)
            let decoded = try JSONDecoder().decode(AudioQuality.self, from: data)
            XCTAssertEqual(decoded, quality)
        }
    }
}
