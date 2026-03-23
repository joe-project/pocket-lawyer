import SwiftUI

struct ThemeModeToggleButton: View {
    @AppStorage("isDarkMode") private var isDarkMode = true

    /// Optional icon size for dense layouts (e.g. file tree).
    var size: CGFloat = 20

    var body: some View {
        Button {
            isDarkMode.toggle()
        } label: {
            Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.system(size: size))
                .foregroundColor(isDarkMode ? .white : .black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
}
