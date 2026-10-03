import SwiftUI

/// Button chrome that uses the native glass button styles on iOS 26.
///
/// `.glass` and `.glassProminent` take no arguments; the accent colour is
/// applied with `.tint(_:)`. These styles are unavailable before iOS 26, hence
/// the material fallback.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color?
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                configuration.label
                    .buttonStyle(.glassProminent)
                    .tint(tint ?? Color.naviAccent)
            } else {
                configuration.label
                    .buttonStyle(.glass)
                    .tint(tint ?? Color.naviAccent)
            }
        } else {
            configuration.label
                .foregroundStyle(prominent ? .white : Color.white.opacity(0.9))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            prominent
                                ? AnyShapeStyle(tint ?? Color.naviAccent)
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

/// Circular transport button used throughout the player.
struct CircleIconButton: View {
    let systemImage: String
    var size: CGFloat = 38
    var iconSize: CGFloat = 17
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? Color.naviAccent : .white.opacity(0.88))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Section header with an optional trailing action.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Standard empty/error state so every screen fails the same way.
struct NaviPlaceholderView: View {
    let systemImage: String
    let title: String
    var message: String?
    var isLoading = false

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.naviAccent)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .symbolRenderingMode(.hierarchical)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// HStack of transport buttons shared by the mini player and full player.
struct TransportControls: View {
    @ObservedObject var engine: PlayerEngine
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: size * 0.62) {
            CircleIconButton(
                systemImage: engine.queue.repeatMode.symbolName,
                size: size,
                iconSize: size * 0.44,
                isActive: engine.queue.repeatMode != .off
            ) { engine.cycleRepeatMode() }

            CircleIconButton(systemImage: "backward.fill", size: size, iconSize: size * 0.44) {
                engine.skipToPrevious()
            }

            CircleIconButton(systemImage: "forward.fill", size: size, iconSize: size * 0.44) {
                engine.skipToNext()
            }

            CircleIconButton(
                systemImage: "shuffle",
                size: size,
                iconSize: size * 0.44,
                isActive: engine.queue.isShuffled
            ) { engine.toggleShuffle() }
        }
    }
}
