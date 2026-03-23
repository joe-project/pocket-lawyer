import SwiftUI

struct AppColors {
    // MARK: Polished shell (soft gray light mode + logo purple accent)
    static let darkBackground = Color.black
    static let darkCard = Color(red: 28/255, green: 28/255, blue: 30/255)
    static let lightBackground = Color(red: 235/255, green: 235/255, blue: 240/255)
    static let lightCard = Color(red: 250/255, green: 250/255, blue: 252/255)
    /// Logo-adjacent purple for strokes / highlights (does not replace asset-based `accent`)
    static let brandPurple = Color(red: 155/255, green: 100/255, blue: 255/255)

    /// Main app background
    static let background = Color("AppBackground")
    /// Sidebar, cards, elevated surfaces
    static let card = Color("AppCard")
    /// Lower layer / depth surface
    static let depth = Color("AppDepth")
    static let cardStroke = Color("AppCardStroke")
    /// Brand accents
    static let primaryAccent = Color(red: 1.0, green: 45.0/255.0, blue: 122.0/255.0)   // #FF2D7A
    static let secondaryAccent = Color(red: 123.0/255.0, green: 63.0/255.0, blue: 228.0/255.0) // #7B3FE4
    static let tertiaryAccent = Color(red: 58.0/255.0, green: 42.0/255.0, blue: 143.0/255.0)   // #3A2A8F

    /// Primary accent token used by existing UI
    static let primary = Color("AppAccentPrimary")
    /// Secondary accent token used by existing UI
    static let accent = Color("AppAccentSecondary")
    static let success     = Color(red: 34/255, green: 197/255, blue: 94/255)      // #22C55E
    static let textPrimary = Color("AppTextPrimary")
    static let textSecondary = Color("AppTextSecondary")
    /// Secondary / quiet buttons
    static let secondaryButton = Color("AppSecondaryButton")

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - App typography (system sans only)
enum AppTypography {
    static let heading = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 16)
    static let bodySemibold = Font.system(size: 16, weight: .semibold)
}

// MARK: - Primary action: blue, flat (no glow)
struct AppButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.bodySemibold)
            .foregroundColor(Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [
                        AppColors.primary,
                        AppColors.accent
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(
                color: configuration.isPressed
                    ? Color(red: 59/255, green: 130/255, blue: 246/255, opacity: 0.18)
                    : Color(red: 59/255, green: 130/255, blue: 246/255, opacity: 0.10),
                radius: configuration.isPressed ? 10 : 8,
                x: 0,
                y: configuration.isPressed ? 4 : 2
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined accent + for attach / add (minimal, no fill).
struct AccentOutlinePlusIcon: View {
    var diameter: CGFloat = 34
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.primary, lineWidth: 2)
                .frame(width: diameter, height: diameter)
            Image(systemName: "plus")
                .font(.system(size: diameter * 0.48, weight: .semibold))
                .foregroundColor(AppColors.primary)
        }
    }
}

// MARK: - Secondary: light gray fill
struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.bodySemibold)
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(AppColors.secondaryButton)
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Minimal tap animation used for “icon” buttons where styling should remain unchanged.
struct AppTapButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Pocket Lawyer: secondary copy (terminal / monospaced)

extension View {
    /// Secondary body text: monospaced system, gray (timeline, evidence, bullets).
    func pocketSecondaryMonospaced(size: CGFloat = 14) -> some View {
        font(.system(size: size, weight: .regular, design: .monospaced))
            .foregroundColor(.gray)
    }
}
