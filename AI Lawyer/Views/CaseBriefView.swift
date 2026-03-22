import SwiftUI

/// Displays the AI-generated case brief at the top of the case workspace: summary, estimated damages, and next recommended step.
struct CaseBriefView: View {
    let analysis: CaseAnalysis

    private var nextRecommendedStep: String {
        analysis.nextSteps.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Continue gathering evidence and consult an attorney."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "⚖", title: "Case Brief")

            Rectangle()
                .fill(AppColors.cardStroke)
                .frame(height: 1)

            if !analysis.summary.isEmpty {
                Text(analysis.summary)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                briefLabel("Estimated damages")
                Text(analysis.estimatedDamages.isEmpty ? "To be assessed." : analysis.estimatedDamages)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                briefLabel("Next recommended step")
                Text(nextRecommendedStep)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private func briefLabel(_ title: String) -> some View {
        Text(title)
            .font(LuxuryTheme.sectionFont(size: 12))
            .foregroundColor(AppColors.textPrimary)
    }
}
