import SwiftUI

/// Displays a vertical checklist for case progress. Completed stages show a green check; pending stages show a gray circle.
struct CaseProgressView: View {
    let progress: CaseProgress

    private var completedCount: Int { progress.stages.filter(\.completed).count }
    private var totalCount: Int { progress.stages.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "📊", title: "Progress")

            Text("\(completedCount) of \(totalCount) steps completed")
                .font(LuxuryTheme.bodyFont(size: 13))
                .foregroundColor(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(progress.stages) { stage in
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: stage.completed ? "checkmark.circle.fill" : "circle")
                            .font(AppTypography.body)
                            .foregroundColor(stage.completed ? Color.progressGreen : Color.progressGray)

                        Text(stage.title)
                            .font(LuxuryTheme.bodyFont(size: 15))
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }
}

private extension Color {
    static let progressGreen = Color(red: 34.0 / 255.0, green: 197.0 / 255.0, blue: 94.0 / 255.0) // #22C55E
    static let progressGray = Color(red: 107.0 / 255.0, green: 114.0 / 255.0, blue: 128.0 / 255.0) // #6B7280
}
