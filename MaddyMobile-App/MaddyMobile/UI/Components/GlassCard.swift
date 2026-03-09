import SwiftUI

// =====================================================
// MARK: - GlassCard
// [TAG: MOBILE_GLASS_CARD]
// =====================================================

struct GlassCard<Content: View>: View {
    let title: String?
    let accent: Color
    @ViewBuilder var content: Content

    init(title: String? = nil, accent: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.24), lineWidth: 1)
                )
        )
    }
}
