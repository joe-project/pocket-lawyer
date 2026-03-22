import SwiftUI

/// Displays a persisted case brief (kept up to date via CaseBriefEngine).
struct CaseBriefCardView: View {
    let brief: CaseBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "⚖", title: "Case Brief")

            Rectangle()
                .fill(AppColors.cardStroke)
                .frame(height: 1)

            if !brief.summary.isEmpty {
                Text(brief.summary)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Estimated damages")
                Text((brief.damagesEstimate?.isEmpty == false) ? (brief.damagesEstimate ?? "") : "To be assessed.")
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("Next recommended step")
                Text(brief.nextRecommendedStep)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(LuxuryTheme.sectionFont(size: 12))
            .foregroundColor(AppColors.textPrimary)
    }
}

