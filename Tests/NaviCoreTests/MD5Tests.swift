import XCTest
@testable import NaviCore

final class MD5Tests: XCTestCase {

    func testKnownVectors() {
        XCTAssertEqual(MD5.hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hex("a"), "0cc175b9c0f1b6a831c399e269772661")
        XCTAssertEqual(MD5.hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(MD5.hex("message digest"), "f96b697d7cb7938d525a2f31aaf161d0")
        XCTAssertEqual(MD5.hex("abcdefghijklmnopqrstuvwxyz"), "c3fcd3d76192e4007dfb496cca67e13b")
        XCTAssertEqual(
            MD5.hex("12345678901234567890123456789012345678901234567890123456789012345678901234567890"),
            "57edf4a22be3c955ac49da2e2107b67a"
        )
    }

    func testMultiBlockInputCrossesPaddingBoundary() {
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 56)), "668a72d5ba17f08e62dabcafad6db14b")
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 63)), "7dc2ca208106a2f703567bdff99d8981")
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 64)), "c1bb4f81d892b2d57947682aeb252456")
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 65)), "1bc932052302d074bdec39795fe00cf6")
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 119)), "ab347a5f68c8a443cfcddc633f12c24f")
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 120)), "fb98667f98096de92620b64f46e1c5b5")
    }

    func testTokenAuthenticationMatchesExpectedDigest() {
        let configuration = ServerConfiguration(
            baseURL: URL(string: "https://music.example.com")!,
            username: "alice",
            password: "hunter2"
        )
        let client = SubsonicClient(
            configuration: configuration,
            transport: StubTransport.json(Fixture.ok()),
            saltProvider: { "abc123" }
        )

        let params = client.authenticationParameters()

        XCTAssertEqual(params["u"], "alice")
        XCTAssertEqual(params["s"], "abc123")
        XCTAssertEqual(params["t"], MD5.hex("hunter2abc123"))
        XCTAssertNil(params["p"])
    }

    func testLegacyPasswordAuthentication() {
        let configuration = ServerConfiguration(
            baseURL: URL(string: "https://music.example.com")!,
            username: "alice",
            password: "hunter2",
            useTokenAuthentication: false
        )
        let client = SubsonicClient(configuration: configuration, transport: StubTransport.json(Fixture.ok()))

        let params = client.authenticationParameters()

        XCTAssertEqual(params["p"], MD5.hex("hunter2"))
        XCTAssertNil(params["t"])
        XCTAssertNil(params["s"])
    }

    func testRandomSaltIsHexAndUnique() {
        let a = SubsonicClient.makeRandomSalt()
        let b = SubsonicClient.makeRandomSalt()

        XCTAssertEqual(a.count, 16)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
    }
}