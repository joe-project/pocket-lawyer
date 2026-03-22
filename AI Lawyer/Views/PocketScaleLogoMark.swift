import SwiftUI

/// Pocket + scale brand mark (rounded pocket + minimal scale glyph).
struct PocketScaleLogoMark: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppColors.primary)

            Image(systemName: "scale")
                .font(.system(size: size * 0.50, weight: .regular))
                .foregroundColor(.white)
                .offset(x: size * 0.06, y: -size * 0.04)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

