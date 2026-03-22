import SwiftUI

struct ContextualMonetizationProModalView: View {
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel

    let onStartTrial: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlock Pocket Lawyer Pro")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("$9.99/month")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary.opacity(0.75))
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                monetizationFeatureRow("Draft legal documents")
                monetizationFeatureRow("Case strategy guidance")
                monetizationFeatureRow("File organization + export")
                monetizationFeatureRow("Priority responses")
            }

            Button {
                onStartTrial()
            } label: {
                Text("Start Free Trial")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppButtonStyle())

            Button {
                onNotNow()
            } label: {
                Text("Not now")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(AppTapButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
        .padding(20)
        .background(LuxuryTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(24)
    }

    private func monetizationFeatureRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.primary)
                .font(.system(size: 16, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
        }
    }
}

