import SwiftUI

struct AppBrandingBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ZenStyle.elevatedSurface)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                Image("AppIconBadge")
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
            .frame(width: 24, height: 24)

            Text("DragonHealth")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("DragonHealth")
    }
}

#Preview {
    AppBrandingBadge()
        .padding()
}
