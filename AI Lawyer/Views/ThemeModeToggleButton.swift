import SwiftUI

struct ThemeModeToggleButton: View {
    @AppStorage("isDarkMode") private var isDarkMode = true

    var size: CGFloat = 20

    var body: some View {
        Button {
            isDarkMode.toggle()
        } label: {
            Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(isDarkMode ? Color.white : Color.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
}
