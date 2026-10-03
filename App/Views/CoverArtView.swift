import NaviCore
import SwiftUI

/// Cover-art view that loads through `ArtworkLoader`.
///
/// Uses the `client` environment value to build authenticated cover-art URLs.
/// Falls back to a gradient placeholder carrying the item's initials so screens
/// never show an empty hole while loading.
struct CoverArtView<Label: View>: View {
    let client: SubsonicClient?
    let artID: String?
    let cornerRadius: CGFloat
    var placeholderTitle: String?
    @ViewBuilder var labelOverlay: Label

    @State private var image: UIImage?
    @State private var didAttemptLoad = false

    /// Caches by (id, size) so different screens requesting the same art share it.
    private var cacheKey: String { "\(artID ?? "none")@\(Int(cornerRadius * 4))" }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.naviArtworkPlaceholder)

                if let placeholderTitle, !placeholderTitle.isEmpty {
                    Text(initials(for: placeholderTitle))
                        .font(.system(size: max(12, cornerRadius * 0.42), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: max(12, cornerRadius * 0.4), weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            labelOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: cacheKey) { await load() }
    }

    private func load() async {
        guard image == nil, !didAttemptLoad || artID != nil else { return }
        didAttemptLoad = true

        if let cached = ArtworkLoader.shared.cached(cacheKey) {
            image = cached
            return
        }

        guard let client, let artID, let url = client.coverArtURL(id: artID, size: requestedSize) else {
            return
        }

        // Scale by screen scale so a small grid cell does not decode a huge image.
        let scale = UIScreen.main.scale
        let maxPixel = max(80, min(1400, cornerRadius * 2 * scale))

        let loaded = await ArtworkLoader.shared.image(
            for: cacheKey,
            url: url,
            maxPixelSize: maxPixel
        )
        if let loaded {
            withAnimation(.easeOut(duration: 0.22)) { image = loaded }
        }
    }

    private var requestedSize: Int {
        let scale = UIScreen.main.scale
        let side = cornerRadius * 2
        let points = [96, 128, 200, 300, 450, 600]
        let target = Int(side * scale)
        return points.min(by: { abs($0 - target) < abs($1 - target) }) ?? 300
    }

    private func initials(for text: String) -> String {
        let words = text.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

extension CoverArtView where Label == EmptyView {
    /// Plain cover art with no overlay.
    init(
        client: SubsonicClient?,
        artID: String?,
        cornerRadius: CGFloat,
        placeholderTitle: String? = nil
    ) {
        self.init(
            client: client,
            artID: artID,
            cornerRadius: cornerRadius,
            placeholderTitle: placeholderTitle
        ) { EmptyView() }
    }
}
