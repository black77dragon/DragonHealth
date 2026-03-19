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
                    accent: accent,
                    isPressed: isPressed,
                    isEnabled: isEnabled
                )
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(isPressed ? 0.98 : 1.0)
    }
}

private struct GlassButtonBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color
    let isPressed: Bool
    let isEnabled: Bool

    var body: some View {
        let fill = colorScheme == .dark
            ? ZenStyle.surface.opacity(isPressed ? 0.82 : 0.94)
            : ZenStyle.elevatedSurface.opacity(isPressed ? 0.94 : 1.0)
        let border = colorScheme == .dark
            ? Color.white.opacity(isEnabled ? 0.10 : 0.05)
            : Color.black.opacity(isEnabled ? 0.10 : 0.05)
        let accentLine = accent.opacity(colorScheme == .dark ? 0.16 : 0.10)
        let shadowOpacity = colorScheme == .dark ? (isPressed ? 0.08 : 0.18) : (isPressed ? 0.03 : 0.08)

        return Capsule()
            .fill(fill)
            .overlay(
                Capsule()
                    .strokeBorder(border, lineWidth: 1)
            )
            .overlay(
                Capsule()
                    .strokeBorder(accentLine, lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: isPressed ? 2 : 6, x: 0, y: isPressed ? 1 : 3)
    }
}

private struct GlassButtonMetrics {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
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
            font = .system(size: 18, weight: .semibold)
        case .compact:
            horizontalPadding = 10
            verticalPadding = 6
            minHeight = 32
            minWidth = nil
            font = .callout
        case .text:
            horizontalPadding = 14
            verticalPadding = 8
            minHeight = 36
            minWidth = nil
            font = nil
        }
    }
}
