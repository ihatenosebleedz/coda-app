import Foundation

public struct SubsonicError: Error, Sendable, Equatable, CustomStringConvertible {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public var isAuthenticationFailure: Bool { code == 40 }

    public var isNotFound: Bool { code == 70 }

    public var isRateLimited: Bool { code == 429 }

    public var description: String {
        switch code {
        case 40: return "Wrong username or password"
        case 50: return "User is not authorised for the given operation"
        case 70: return "The requested data was not found"
        default: return message
        }
    }
}

public enum ClientError: Error, Sendable, Equatable {
    case invalidServerURL
    case invalidRequest(String)
    case unreachable(String)
    case transport(String)
    case decoding(String)
    case subsonic(SubsonicError)
}

extension ClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "That server address doesn't look right. Include http:// or https://"
        case .invalidRequest(let detail):
            return detail
        case .unreachable(let detail):
            return "Couldn't reach the server: \(detail)"
        case .transport(let detail):
            return "Connection failed: \(detail)"
        case .decoding(let detail):
            return "The server sent something unexpected: \(detail)"
        case .subsonic(let error):
            return error.description
        }
    }
}

public enum JSONCoding {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]

            if let date = fractional.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }

            let trimmed = raw.split(separator: ".").first.map(String.init) ?? raw
            if let date = plain.date(from: trimmed) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised date: \(raw)"
            )
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}