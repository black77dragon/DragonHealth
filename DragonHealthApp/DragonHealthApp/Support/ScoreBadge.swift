import SwiftUI

enum ScoreColor {
    static func color(for score: Double) -> Color {
        let clamped = min(max(score, 0), 100)
        let hue = (clamped / 100.0) * 0.33
        return Color(hue: hue, saturation: 0.85, brightness: 0.9)
    }
}

struct ScoreBadge: View {
    let score: Double

    var body: some View {
        let clamped = min(max(score, 0), 100)
        let display = Int(clamped.rounded())
        let color = ScoreColor.color(for: clamped)
        Text("Score \(display)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel("Score \(display)")
    }
}
