import SwiftUI

/// Displays evidence verification alerts (missing evidence, contradictions, timeline conflicts) inside the case dashboard.
struct EvidenceAlertsView: View {
    let alerts: [EvidenceAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "⚠️", title: "Evidence Alerts")
            if alerts.isEmpty {
                emptyContent
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(alerts) { alert in
                        alertRow(alert)
                    }
                }
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private var emptyContent: some View {
        Text("No evidence alerts. Verification will flag missing evidence, contradictions, or unclear timeline events.")
            .font(LuxuryTheme.bodyFont(size: 15))
            .foregroundColor(AppColors.textPrimary)
    }

    private func alertRow(_ alert: EvidenceAlert) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(AppColors.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(LuxuryTheme.sectionFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                Text(alert.message)
                    .font(LuxuryTheme.bodyFont(size: 14))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(LuxuryTheme.surfaceCard)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
        )
    }
}
