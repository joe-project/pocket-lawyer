import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(AppTypography.heading)
                    .foregroundColor(AppColors.textPrimary)

                privacyPledgeCard

                Text("Policy details")
                    .font(AppTypography.heading)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.top, 8)

                policySection(
                    title: "Information we collect",
                    body: "We may collect information you provide when using the app, including messages you send, case details, and documents you create or upload. If you use cloud or account features, we may store data necessary to sync your cases and preferences."
                )
                policySection(
                    title: "How we use it",
                    body: "We use this information to provide and improve the AI Lawyer service, to generate responses and documents you request, and to maintain your cases and timeline within the app."
                )
                policySection(
                    title: "Data storage and security",
                    body: "Data may be stored on your device and, where applicable, on our servers or third‑party services. We take reasonable steps to protect your data but cannot guarantee absolute security."
                )
                policySection(
                    title: "Third parties",
                    body: "To provide AI features, we may send your inputs to third‑party AI providers. Their use of data is governed by their respective privacy policies."
                )
                policySection(
                    title: "Your choices",
                    body: "You can control what information you provide. Optional programs—such as contributing anonymized legal data to improve the system or participating in a marketplace—require your explicit opt‑in. Deleting the app may remove local data; contact us for questions about other stored data."
                )
                policySection(
                    title: "Updates",
                    body: "We may update this policy from time to time. Continued use of the app after changes constitutes acceptance of the updated policy."
                )
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyPledgeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your data stays private.")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)

            Group {
                Text("All conversations, documents, and evidence are stored securely and are never shared without your explicit permission.")
                Text("You may choose to contribute anonymized legal data to improve the system or participate in the marketplace — but only if you opt in.")
                Text("You are always in control of your information.")
            }
            .font(AppTypography.body)
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuxuryTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)
            Text(body)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
