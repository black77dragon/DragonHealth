import SwiftUI

enum ZenStyle {
    static let pageBackground = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemBackground)
    static let elevatedSurface = Color(.systemBackground)
    static let subtleAccent = Color.accentColor.opacity(0.12)
}

enum ZenSpacing {
    static let compact: CGFloat = 4
    static let text: CGFloat = 8
    static let group: CGFloat = 12
    static let section: CGFloat = 16
    static let card: CGFloat = 20
}

extension View {
    func zenPageBackground() -> some View {
        background(ZenPageBackground())
    }

    func zenCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(ZenCardModifier(cornerRadius: cornerRadius))
    }

    func zenEyebrow() -> some View {
        modifier(ZenEyebrowModifier())
    }

    func zenHeroTitle() -> some View {
        modifier(ZenHeroTitleModifier())
    }

    func zenSectionTitle() -> some View {
        modifier(ZenSectionTitleModifier())
    }

    func zenSupportText() -> some View {
        modifier(ZenSupportTextModifier())
    }

    func zenMetricLabel() -> some View {
        modifier(ZenMetricLabelModifier())
    }

    func zenMetricValue() -> some View {
        modifier(ZenMetricValueModifier())
    }
}

private struct ZenPageBackground: View {
    var body: some View {
        ZenStyle.pageBackground
            .ignoresSafeArea()
    }
}

private struct ZenCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? ZenStyle.surface.opacity(0.94) : ZenStyle.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05),
                radius: colorScheme == .dark ? 10 : 12,
                x: 0,
                y: colorScheme == .dark ? 4 : 6
            )
    }
}

private struct ZenEyebrowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

private struct ZenHeroTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .lineSpacing(2)
    }
}

private struct ZenSectionTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

private struct ZenSupportTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
    }
}

private struct ZenMetricLabelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct ZenMetricValueModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline.monospacedDigit())
            .foregroundStyle(.primary)
    }
}
