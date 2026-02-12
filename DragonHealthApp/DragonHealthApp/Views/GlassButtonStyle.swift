import SwiftUI

enum GlassButtonKind {
    case text
    case icon
    case compact
}

struct GlassButtonStyle: ButtonStyle {
    let kind: GlassButtonKind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let accent = Color.accentColor

        return GlassButtonChrome(
            kind: kind,
            accent: accent,
            isPressed: configuration.isPressed
        ) {
            configuration.label
        }
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

extension View {
    func glassButton(_ kind: GlassButtonKind = .text) -> some View {
        buttonStyle(GlassButtonStyle(kind: kind))
    }

    func glassLabel(_ kind: GlassButtonKind = .text) -> some View {
        GlassButtonLabel(kind: kind) {
            self
        }
    }
}

private struct GlassButtonLabel<Content: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    let kind: GlassButtonKind
    let content: Content

    init(kind: GlassButtonKind, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.content = content()
    }

    var body: some View {
        GlassButtonChrome(
            kind: kind,
            accent: Color.accentColor,
            isPressed: false
        ) {
            content
        }
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

private struct GlassButtonChrome<Content: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    let kind: GlassButtonKind
    let accent: Color
    let isPressed: Bool
    let content: Content

    init(kind: GlassButtonKind, accent: Color, isPressed: Bool, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.accent = accent
        self.isPressed = isPressed
        self.content = content()
    }

    var body: some View {
        let metrics = GlassButtonMetrics(kind: kind)
        content
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .font(metrics.font)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(minWidth: metrics.minWidth, minHeight: metrics.minHeight)
            .background(
                GlassButtonBackground(
                    cornerRadius: metrics.cornerRadius,
                    accent: accent,
                    isPressed: isPressed,
                    isEnabled: isEnabled
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .scaleEffect(isPressed ? 0.98 : 1.0)
    }
}

private struct GlassButtonBackground: View {
    let cornerRadius: CGFloat
    let accent: Color
    let isPressed: Bool
    let isEnabled: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemBackground).opacity(0.55))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(isPressed ? 0.05 : 0.12),
                                accent.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isPressed ? 0.14 : 0.32),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isEnabled ? 0.75 : 0.35),
                                Color.white.opacity(isEnabled ? 0.16 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(isPressed ? 0.08 : 0.16), radius: isPressed ? 3 : 10, x: 0, y: isPressed ? 1 : 5)
    }
}

private struct GlassButtonMetrics {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let minWidth: CGFloat?
    let minHeight: CGFloat
    let font: Font?

    init(kind: GlassButtonKind) {
        switch kind {
        case .icon:
            horizontalPadding = 12
            verticalPadding = 8
            minHeight = 36
            minWidth = 44
            cornerRadius = 18
            font = .system(size: 18, weight: .semibold)
        case .compact:
            horizontalPadding = 10
            verticalPadding = 6
            minHeight = 32
            minWidth = nil
            cornerRadius = 16
            font = .callout
        case .text:
            horizontalPadding = 14
            verticalPadding = 8
            minHeight = 36
            minWidth = nil
            cornerRadius = 18
            font = nil
        }
    }
}
