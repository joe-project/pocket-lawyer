import SwiftUI

/// Minimal Pocket Law mark: rounded square (pocket) + offset vertical bar (document). Flat coral on light ground.
enum PocketLawBrand {
    static let coral = Color(red: 1, green: 122 / 255, blue: 89 / 255) // #FF7A59
    static let canvas = Color(red: 0.97, green: 0.97, blue: 0.98) // light gray
}

struct PocketLawLogoView: View {
    var size: CGFloat = 88
    /// When true, logo sits on light gray; when false, only the mark (for dark backgrounds use inverted colors separately).
    var showsCanvas: Bool = true

    var body: some View {
        ZStack {
            if showsCanvas {
                PocketLawBrand.canvas
            }
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(PocketLawBrand.coral)
                RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size * 0.14, height: size * 0.52)
                    .offset(x: size * 0.09, y: -size * 0.04)
            }
            .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: showsCanvas ? size * 0.2 : 0, style: .continuous))
    }
}

#Preview("Logo") {
    VStack(spacing: 24) {
        PocketLawLogoView(size: 120)
        PocketLawLogoView(size: 64)
        PocketLawLogoView(size: 44, showsCanvas: false)
            .padding(40)
            .background(Color.black)
    }
    .padding()
}
