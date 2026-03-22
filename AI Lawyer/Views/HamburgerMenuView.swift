import SwiftUI

struct HamburgerMenuView: View {
    @Binding var showLegalDisclaimer: Bool
    @Binding var showPrivacyPolicy: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showFeatureSuggestion = false

    var body: some View {
        NavigationView {
            List {
                Button {
                    showLegalDisclaimer = true
                    dismiss()
                } label: {
                    Label("Legal Disclaimer", systemImage: "doc.text.fill")
                        .font(LuxuryTheme.bodyFont(size: 16))
                        .foregroundColor(AppColors.textPrimary)
                }
                .listRowBackground(LuxuryTheme.surfaceCard)
                Button {
                    showPrivacyPolicy = true
                    dismiss()
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                        .font(LuxuryTheme.bodyFont(size: 16))
                        .foregroundColor(AppColors.textPrimary)
                }
                .listRowBackground(LuxuryTheme.surfaceCard)
                Button {
                    showFeatureSuggestion = true
                } label: {
                    Label("Suggest a Feature — Earn $", systemImage: "sparkles")
                        .font(LuxuryTheme.bodyFont(size: 16))
                        .foregroundColor(AppColors.textPrimary)
                }
                .listRowBackground(LuxuryTheme.surfaceCard)
                Button {
                    // Settings placeholder
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                        .font(LuxuryTheme.bodyFont(size: 16))
                        .foregroundColor(AppColors.textPrimary)
                }
                .listRowBackground(LuxuryTheme.surfaceCard)
            }
            .scrollContentBackground(.hidden)
            .background(LuxuryTheme.primaryBackground)
            .navigationTitle("Menu")
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .sheet(isPresented: $showFeatureSuggestion) {
            FeatureSuggestionSheet()
        }
    }
}
