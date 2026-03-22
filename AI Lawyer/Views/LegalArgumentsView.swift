import SwiftUI

/// Displays structured legal arguments (IRAC) inside the case workspace.
struct LegalArgumentsView: View {
    let arguments: [LegalArgument]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "⚖️", title: "Legal Arguments")
            Rectangle()
                .fill(LuxuryTheme.cardBorder)
                .frame(height: 1)
            if arguments.isEmpty {
                emptyContent
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(arguments.enumerated()), id: \.offset) { _, argument in
                        argumentCard(argument)
                    }
                }
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private var emptyContent: some View {
        Text("No legal arguments yet. Build arguments from the case analysis, evidence, and timeline to see IRAC-style claims here.")
            .font(LuxuryTheme.bodyFont(size: 15))
            .foregroundColor(AppColors.textPrimary)
    }

    private func argumentCard(_ argument: LegalArgument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionRow(label: "Claim", content: argument.claim)
            sectionRow(label: "Legal Rule", content: argument.legalRule)
            sectionRow(label: "Facts", content: argument.facts)
            evidenceSection(items: argument.evidence)
            sectionRow(label: "Conclusion", content: argument.conclusion)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuxuryTheme.surfaceCard)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
        )
    }

    private func sectionRow(label: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(LuxuryTheme.sectionFont(size: 12))
                .foregroundColor(AppColors.textPrimary)
            Text(content.isEmpty ? "—" : content)
                .font(LuxuryTheme.bodyFont(size: 15))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func evidenceSection(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Evidence")
                .font(LuxuryTheme.sectionFont(size: 12))
                .foregroundColor(AppColors.textPrimary)
            if items.isEmpty {
                Text("—")
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(LuxuryTheme.bodyFont(size: 15))
                                .foregroundColor(AppColors.primary)
                            Text(item)
                                .font(LuxuryTheme.bodyFont(size: 15))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }
                }
            }
        }
    }
}
