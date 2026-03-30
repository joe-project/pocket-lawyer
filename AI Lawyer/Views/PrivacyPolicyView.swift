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
                    body: "Pocket Lawyer uses the information you choose to provide, such as messages, case details, and documents, to answer your questions and build materials inside the app. Your case files, evidence, and documents are stored locally on your device, not in a cloud drive operated by us."
                )
                policySection(
                    title: "How we use it",
                    body: "We use your information only to provide the features you ask for, including answering questions, drafting documents, organizing evidence, and helping you build a case. We do not use your private case content for public marketing or general sharing."
                )
                policySection(
                    title: "Data storage and security",
                    body: "Your documents, files, and case materials are stored locally on your phone. We do not keep a cloud copy of your case folder contents as part of the normal product experience. We take reasonable steps to protect the app and its transmissions, but no system can promise absolute security."
                )
                policySection(
                    title: "AI processing and anonymization",
                    body: "When you use the AI chat, information may be sent through AI infrastructure to generate a response. Pocket Lawyer is designed to anonymize AI conversations in the cloud wherever possible, and the full case materials you keep in your folders remain stored locally on your device."
                )
                policySection(
                    title: "Sharing and permission",
                    body: "We do not share your information with anyone unless you give express permission. Optional features that involve sharing, including anonymized marketplace or contribution programs, require a clear opt-in from you first."
                )
                policySection(
                    title: "Your choices",
                    body: "You control what you enter into Pocket Lawyer and whether you share anything at all. If you delete the app, locally stored case files on the device may also be removed unless you have backed them up yourself."
                )
                policySection(
                    title: "Updates",
                    body: "We may update this policy from time to time. If the privacy model changes in a material way, the updated policy will reflect that change clearly."
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
            Text("Why is Pocket Lawyer Different?")
                .font(AppTypography.heading)
                .foregroundColor(AppColors.textPrimary)

            Group {
                Text("Pocket Lawyer is built around privacy first. Your case documents, evidence, and folder contents are stored locally on your phone and are not kept by us in a cloud case database.")
                Text("When AI is used in the cloud, Pocket Lawyer is designed to anonymize the conversation wherever possible before processing.")
                Text("We never share your information with anyone unless you give express permission.")
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
