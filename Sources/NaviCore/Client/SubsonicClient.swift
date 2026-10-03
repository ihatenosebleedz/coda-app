import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]

    public init(url: URL, method: String = "GET", headers: [String: String] = [:]) {
        self.url = url
        self.method = method
        self.headers = headers
    }
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]

    public init(statusCode: Int, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.headers = headers
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> (Data, HTTPResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> (Data, HTTPResponse) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = 30
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: urlRequest)
        let http = response as? HTTPURLResponse

        return (
            data,
            HTTPResponse(
                statusCode: http?.statusCode ?? 0,
                headers: http.flatMap { response in
                    var out: [String: String] = [:]
                    for (key, value) in response.allHeaderFields {
                        if let key = key as? String, let value = value as? String {
                            out[key.lowercased()] = value
                        }
                    }
                    return out
                } ?? [:]
            )
        )
    }
}

public struct ServerConfiguration: Sendable, Equatable, Codable {
    public var baseURL: URL
    public var username: String
    public var password: String
    public var apiVersion: String
    public var useTokenAuthentication: Bool

    public init(
        baseURL: URL,
        username: String,
        password: String,
        apiVersion: String = "1.16.1",
        useTokenAuthentication: Bool = true
    ) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.apiVersion = apiVersion
        self.useTokenAuthentication = useTokenAuthentication
    }

    public static func normalise(urlString: String) -> URL? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            // ok
        } else {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }
}

public enum AudioQuality: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case original
    case lossless
    case high
    case medium
    case low

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .original: return "Original"
        case .lossless: return "Lossless"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Data Saver"
        }
    }

    public var detail: String {
        switch self {
        case .original: return "No limit"
        case .lossless: return "Up to 1411 kbps"
        case .high: return "Up to 320 kbps"
        case .medium: return "Up to 192 kbps"
        case .low: return "Up to 96 kbps"
        }
    }

    public var maxBitRate: Int? {
        switch self {
        case .original: return nil
        case .lossless: return 1411
        case .high: return 320
        case .medium: return 192
        case .low: return 96
        }
    }

    public var streamFormat: String {
        switch self {
        case .original: return "raw"
        default: return "mp3"
        }
    }
}

extension Song {
    static let avPlayerPlayableSuffixes: Set<String> = [
        "mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "caf", "flac", "alac", "m4b"
    ]

    public var isDirectlyPlayableByAVPlayer: Bool {
        guard let suffix, !suffix.isEmpty else { return false }
        return Song.avPlayerPlayableSuffixes.contains(suffix.lowercased())
    }

    public var resolvedSuffix: String {
        if let transcodedSuffix, !transcodedSuffix.isEmpty { return transcodedSuffix.lowercased() }
        return suffix?.lowercased() ?? ""
    }
}

public struct SubsonicClient: Sendable {
    public let configuration: ServerConfiguration
    private let transport: any HTTPTransport
    private let saltProvider: @Sendable () -> String

    public init(
        configuration: ServerConfiguration,
        transport: any HTTPTransport = URLSessionTransport(),
        saltProvider: @escaping @Sendable () -> String = { SubsonicClient.makeRandomSalt() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.saltProvider = saltProvider
    }

    public static func makeRandomSalt(length: Int = 16) -> String {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("0123456789abcdef")
        return String(
            (0..<length).map { _ in alphabet[Int(generator.next(upperBound: UInt64(alphabet.count)))] }
        )
    }

    func authenticationParameters() -> [String: String] {
        let salt = saltProvider()
        if configuration.useTokenAuthentication {
            return [
                "u": configuration.username,
                "t": MD5.hex(configuration.password + salt),
                "s": salt
            ]
        }
        return [
            "u": configuration.username,
            "p": MD5.hex(configuration.password)
        ]
    }

    public func url(
        for method: String,
        parameters: [String: String] = [:],
        authenticated: Bool = true
    ) -> URL? {
        let base = configuration.baseURL.appendingPathComponent("rest").appendingPathComponent(method)

        var items: [URLQueryItem] = [
            URLQueryItem(name: "v", value: configuration.apiVersion),
            URLQueryItem(name: "f", value: "json"),
            URLQueryItem(name: "c", value: "Navi")
        ]

        if authenticated {
            items.append(contentsOf: authenticationParameters().map {
                URLQueryItem(name: $0.key, value: $0.value)
            })
        }

        items.append(contentsOf: parameters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) })

        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = items
        return components.url
    }

    public func coverArtURL(id: String, size: Int? = 600) -> URL? {
        var params: [String: String] = ["id": id]
        if let size { params["size"] = String(size) }
        return url(for: "getCoverArt", parameters: params)
    }

    public func streamParameters(for song: Song, quality: AudioQuality) -> [String: String] {
        var params: [String: String] = ["id": song.id]

        let codecUnsupported = !song.isDirectlyPlayableByAVPlayer
        let needsTranscoding = quality != .original || codecUnsupported

        guard needsTranscoding else {
            params["format"] = "raw"
            return params
        }

        params["maxBitRate"] = String(quality.maxBitRate ?? 320)
        params["format"] = codecUnsupported || quality != .original ? "mp3" : "raw"

        return params
    }

    public func streamURL(for song: Song, quality: AudioQuality) -> URL? {
        url(for: "stream", parameters: streamParameters(for: song, quality: quality))
    }

    public func downloadURL(for song: Song) -> URL? {
        url(for: "download", parameters: ["id": song.id])
    }

    func perform<Response: Decodable>(
        _ method: String,
        _ parameters: [String: String] = [:]
    ) async throws -> Response {
        guard let requestURL = url(for: method, parameters: parameters) else {
            throw ClientError.invalidServerURL
        }

        let request = HTTPRequest(
            url: requestURL,
            method: "GET",
            headers: ["Accept": "application/json"]
        )

        let data: Data
        let response: HTTPResponse

        do {
            (data, response) = try await transport.send(request)
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }

        guard response.statusCode == 200 else {
            throw ClientError.unreachable("HTTP \(response.statusCode)")
        }

        let decoder = JSONCoding.makeDecoder()
        let envelope = SubsonicEnvelope<Response>(
            responseKey: SubsonicClient.defaultResponseKey(for: method)
        )

        do {
            return try envelope.decodePayload(from: data, using: decoder)
        } catch let error as SubsonicError {
            throw ClientError.subsonic(error)
        } catch let error as DecodingError {
            throw ClientError.decoding(String(describing: error))
        } catch {
            throw ClientError.decoding(error.localizedDescription)
        }
    }

    /// Subsonic nests container results under a key derived from the method name:
    /// `getAlbumList2` -> `albumList2`, `getIndexes` -> `indexes`. Methods that
    /// return nothing useful (star, scrobble, …) opt out with an empty response key.
    static func defaultResponseKey(for method: String) -> String? {
        switch method {
        case "ping", "star", "unstar", "setRating", "nowPlaying", "scrobble",
             "updatePlaylist", "deletePlaylist":
            return nil
        case "search3":
            return "searchResult3"
        case "search2":
            return "searchResult2"
        case "getAlbumList":
            return "albumList"
        case "createPlaylist":
            return "playlist"
        default:
            var base = method
            if base.hasPrefix("get") { base.removeFirst(3) }
            guard let first = base.first else { return nil }
            return String(first).lowercased() + base.dropFirst()
        }
    }
}

struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct SubsonicEnvelope<Payload: Decodable> {
    /// When set, the payload is read from this key inside `subsonic-response`.
    /// When nil, the payload is decoded from the response object itself.
    let responseKey: String?

    init(responseKey: String?) {
        self.responseKey = responseKey
    }

    private struct EnvelopeBody: Decodable {
        struct ErrorBody: Decodable {
            let code: Int?
            let message: String?
        }

        private enum Keys: String, CodingKey {
            case response = "subsonic-response"
            case status
            case error
        }

        let status: String?
        let error: ErrorBody?
        let payload: JSONValue

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let inner = try container.nestedContainer(keyedBy: Keys.self, forKey: .response)
            status = try inner.decodeIfPresent(String.self, forKey: .status)
            error = try inner.decodeIfPresent(ErrorBody.self, forKey: .error)
            payload = try container.decode(JSONValue.self, forKey: .response)
        }
    }

    private struct Wrapped: Encodable {
        let value: JSONValue
    }

    func decodePayload(from data: Data, using decoder: JSONDecoder) throws -> Payload {
        let body = try decoder.decode(EnvelopeBody.self, from: data)

        if body.status == "failed" {
            throw SubsonicError(
                code: body.error?.code ?? 0,
                message: body.error?.message ?? "Unknown Subsonic error"
            )
        }

        let payloadValue: JSONValue
        if let responseKey {
            guard let object = body.payload.objectValue, let nested = object[responseKey] else {
                throw DecodingError.keyNotFound(
                    AnyCodingKey(stringValue: responseKey),
                    .init(codingPath: [], debugDescription: "No '\(responseKey)' key in subsonic-response")
                )
            }
            payloadValue = nested
        } else {
            payloadValue = body.payload
        }

        return try decoder.decode(Payload.self, from: try Self.encode(payloadValue))
    }

    private static func encode(_ value: JSONValue) throws -> Data {
        try JSONEncoder().encode(value)
    }
}