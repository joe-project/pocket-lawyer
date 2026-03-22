import SwiftUI

// MARK: - App design system (light, minimal)

enum LuxuryTheme {

    static let primaryBackground = AppColors.background
    /// Subtle strip / alternate panel (slightly distinct from main bg)
    static let secondaryBackground = AppColors.depth
    static let surfaceCard = AppColors.card

    static let primaryText = AppColors.textPrimary
    static let secondaryText = AppColors.textSecondary
    static let mutedText = AppColors.textSecondary

    static let ivoryHighlight = AppColors.textPrimary

    static let cardBorder = AppColors.cardStroke
    /// Minimal elevation only
    static let cardShadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.05)

    static let navBarBorder = AppColors.tertiaryAccent.opacity(0.45)

    static func titleFont(size: CGFloat = 26) -> Font { AppTypography.heading }
    static func sectionFont(size: CGFloat = 17) -> Font {
        size >= 17 ? AppTypography.heading : AppTypography.body
    }
    static func bodyFont(size: CGFloat = 15) -> Font { AppTypography.body }
    static func buttonFont(size: CGFloat = 15) -> Font { AppTypography.bodySemibold }

    static let workspaceCardSpacing: CGFloat = 20
    static let workspaceCardPadding: CGFloat = 20
}

extension Color {
    init(hex: Int) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct LuxuryCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(LuxuryTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: LuxuryTheme.cardShadowColor,
                radius: 6,
                x: 0,
                y: 2
            )
            .cornerRadius(20)
    }

    private var borderColor: Color {
        // Requirement: rgba(255,255,255,0.06)
        return Color.white.opacity(0.06)
    }
}

extension View {
    func luxuryCard() -> some View {
        modifier(LuxuryCardStyle())
    }
}

struct WorkspaceCardHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.textPrimary)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
        }
    }
}

struct LuxurySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.bodySemibold)
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppColors.secondaryButton)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
