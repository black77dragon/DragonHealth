import SwiftUI

struct AppBrandingBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image("AppIconBadge")
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
            .frame(width: 24, height: 24)

            Text("DragonHealth")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.primary, Color.primary.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .accessibilityLabel("DragonHealth")
    }
}

#Preview {
    AppBrandingBadge()
        .padding()
}
