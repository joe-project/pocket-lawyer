import SwiftUI

struct HamburgerMenuView: View {
    @Binding var showLegalDisclaimer: Bool
    @Binding var showPrivacyPolicy: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Button {
                    showLegalDisclaimer = true
                    dismiss()
                } label: {
                    Label("Legal Disclaimer", systemImage: "doc.text.fill")
                }
                Button {
                    showPrivacyPolicy = true
                    dismiss()
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                Button {
                    // Settings placeholder
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .navigationTitle("Menu")
        }
    }
}
