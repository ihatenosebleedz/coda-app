import Foundation
import NaviCore
import UIKit

/// In-memory artwork cache plus an async loader.
///
/// `AsyncImage` would refetch cover art on every list cell appearance and gives
/// no control over the auth header, so navigation requests URLs through the
/// NaviCore client instead. Results are cached by (id, size) and downsampled
/// with ImageIO so a 600px cover never becomes a full-screen bitmap.
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 240
    }

    func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// Loads artwork, returning the cached image immediately when possible.
    func image(for key: String, url: URL?, maxPixelSize: CGFloat) async -> UIImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        guard let url else { return nil }

        lock.lock()
        if let existing = inFlight[key] {
            lock.unlock()
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            defer {
                self.lock.lock()
                self.inFlight[key] = nil
                self.lock.unlock()
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await self.session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }
                self.cache.setObject(image, forKey: key as NSString)
                return image
            } catch {
                return nil
            }
        }

        inFlight[key] = task
        lock.unlock()

        return await task.value
    }

    /// Decodes and downsamples in one step so large JPEGs never fully inflate.
    nonisolated static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    func clear() {
        cache.removeAllObjects()
        lock.lock()
        inFlight.removeAll()
        lock.unlock()
    }
}

/// Formats a duration in seconds as `m:ss` or `h:mm:ss`.
func formatDuration(_ seconds: Int?) -> String {
    guard let seconds, seconds > 0 else { return "--:--" }

    let total = seconds
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

/// `1,234 songs`
func formatCount(_ count: Int?, singular: String, plural: String? = nil) -> String {
    guard let count else { return "" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let number = formatter.string(from: NSNumber(value: count)) ?? String(count)
    return "\(number) \(count == 1 ? singular : (plural ?? singular + "s"))"
}

/// `FLAC · 44.1 kHz · 24 bit` style codec summary, or nil when unknown.
func describeCodec(_ song: Song) -> String? {
    guard let suffix = song.suffix?.uppercased(), !suffix.isEmpty else { return nil }

    var parts = [suffix]

    if let bitRate = song.bitRate, bitRate > 0 {
        parts.append("\(bitRate / 1000) kbps")
    } else if let duration = song.duration, let size = song.size, duration > 0, size > 0 {
        // Fall back to a computed average bitrate when the server omits it.
        let kbps = Int((Double(size) * 8 / Double(duration)) / 1000)
        if kbps > 0 { parts.append("\(kbps) kbps") }
    }

    return parts.joined(separator: " · ")
}

/// Human-friendly release year.
func formatYear(_ year: Int?) -> String? {
    guard let year, year > 0 else { return nil }
    return String(year)
}
