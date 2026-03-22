import SwiftUI

struct FeatureSuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var didSubmit = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Got an idea?")
                    .font(LuxuryTheme.sectionFont(size: 18))
                    .foregroundColor(AppColors.textPrimary)

                Text("Tell us what would make AI Lawyer better. If we ship it, we may reach out about a small cash reward.")
                    .font(LuxuryTheme.bodyFont(size: 14))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $text)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(10)
                    .background(LuxuryTheme.surfaceCard)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                    )
                    .frame(minHeight: 160)

                if didSubmit {
                    Text("Saved. Thanks — we read every suggestion.")
                        .font(LuxuryTheme.bodyFont(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer()
            }
            .padding(20)
            .background(LuxuryTheme.primaryBackground)
            .navigationTitle("Suggest a Feature — Earn $")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        FeatureSuggestionStore.shared.add(text: text)
                        didSubmit = true
                        text = ""
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

