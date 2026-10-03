import SwiftUI

/// Colour palette and the Liquid Glass compatibility layer.
///
/// `glassEffect` only exists on iOS 26+. Navi deploys back to iOS 17, so every
/// glass surface in the app goes through `GlassSurface` (or `.naviGlass()`)
/// instead of calling Apple's API directly. That keeps all availability checks
/// in this one file: on iOS 26 the real Liquid Glass effect is used, and on
/// older systems it degrades to an equivalent blur-based material.
extension Color {
    /// Deep background gradient used behind the whole app.
    static let naviBackgroundTop = Color(red: 0.05, green: 0.05, blue: 0.09)
    static let naviBackgroundBottom = Color(red: 0.10, green: 0.06, blue: 0.18)

    /// Accent used for play buttons and the scrubber.
    static let naviAccent = Color(red: 0.62, green: 0.36, blue: 0.98)

    /// Secondary accent for the "now playing" state.
    static let naviHighlight = Color(red: 0.36, green: 0.85, blue: 0.72)

    static let naviCanvas = Color(red: 0.07, green: 0.07, blue: 0.11)

    /// Standard artwork placeholder.
    static let naviArtworkPlaceholder = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.15, blue: 0.30),
            Color(red: 0.10, green: 0.09, blue: 0.17)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Full-screen background: a static gradient plus slow drifting colour blobs so
/// that the glass surfaces have something interesting to refract.
struct NaviBackground: View {
    /// Animated phase, advanced from a TimelineView-free timer by the caller.
    var phase: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.naviBackgroundTop, .naviBackgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let t = phase

                Circle()
                    .fill(Color.naviAccent.opacity(0.32))
                    .frame(width: proxy.size.width * 1.1)
                    .blur(radius: 70)
                    .offset(
                        x: -proxy.size.width * 0.25 + sin(t * 0.4) * proxy.size.width * 0.18,
                        y: proxy.size.height * 0.18 + cos(t * 0.3) * 60
                    )

                Circle()
                    .fill(Color.naviHighlight.opacity(0.22))
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 80)
                    .offset(
                        x: proxy.size.width * 0.28 + cos(t * 0.35) * proxy.size.width * 0.15,
                        y: proxy.size.height * 0.62 + sin(t * 0.25) * 70
                    )
            }
        }
        .ignoresSafeArea()
    }
}

/// Wraps a view in Liquid Glass on iOS 26+, with a blur-material fallback.
///
/// Applied as the last appearance-affecting modifier, as Apple's docs require.
///
/// Note the API shapes here: `Glass.tint(_:)` takes a non-optional `Color`,
/// `interactive()` takes no arguments, and `.glassEffect(_:in:)` has a default
/// `isEnabled` parameter we do not need to pass.
struct GlassSurface<Content: View>: View {
    var shape: Shape = .rect(cornerRadius: 22)
    var tint: Color?
    var interactive: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .background(
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var result = Glass.regular
        if let tint { result = result.tint(tint) }
        if interactive { result = result.interactive() }
        return result
    }
}

extension View {
    /// Convenience wrapper so call sites read as `.naviGlass(.rect(cornerRadius: 16))`.
    func naviGlass(
        in shape: Shape = .rect(cornerRadius: 22),
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        GlassSurface(shape: shape, tint: tint, interactive: interactive) { self }
    }
}

/// Fills the available space with the app background.
struct NaviBackgroundContainer<Content: View>: View {
    var phase: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            NaviBackground(phase: phase)
            content
        }
    }
}
