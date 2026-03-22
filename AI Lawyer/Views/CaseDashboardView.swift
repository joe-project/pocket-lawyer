import SwiftUI

/// A suggested action derived from case analysis; tapping it typically navigates to the relevant workspace section.
struct SuggestedAction: Identifiable {
    let id: String
    let title: String
    let section: CaseWorkspaceSection
}

// MARK: - Suggested Actions card (standalone for workspace card layout)
struct SuggestedActionsCardView: View {
    let analysis: CaseAnalysis
    var onSuggestedAction: ((CaseWorkspaceSection) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "📋", title: "Suggested Actions")
            suggestedActionsContent
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    @ViewBuilder
    private var suggestedActionsContent: some View {
        let actions = suggestedActions(from: analysis)
        if actions.isEmpty {
            Text("No suggested actions right now.")
                .pocketSecondaryMonospaced(size: 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(actions) { action in
                    Button {
                        onSuggestedAction?(action.section)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: actionIcon(for: action.section))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.primary)
                            Text(action.title)
                                .pocketSecondaryMonospaced(size: 14)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppTypography.body)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(LuxuryTheme.surfaceCard)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func suggestedActions(from analysis: CaseAnalysis) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []
        let docLower = analysis.documents.map { $0.lowercased() }.joined(separator: " ")
        let nextLower = analysis.nextSteps.map { $0.lowercased() }.joined(separator: " ")
        let evidenceLower = analysis.evidenceNeeded.map { $0.lowercased() }.joined(separator: " ")
        if docLower.contains("demand letter") || nextLower.contains("demand") {
            actions.append(SuggestedAction(id: "demand", title: "Generate Demand Letter", section: .documents))
        }
        if !analysis.evidenceNeeded.isEmpty || evidenceLower.contains("evidence") {
            actions.append(SuggestedAction(id: "evidence", title: "Upload Evidence", section: .evidence))
        }
        actions.append(SuggestedAction(id: "witness", title: "Add Witness Statement", section: .recordings))
        if docLower.contains("complaint") || nextLower.contains("file") || nextLower.contains("complaint") {
            actions.append(SuggestedAction(id: "complaint", title: "Draft Complaint", section: .documents))
        }
        if actions.count < 2 {
            if !actions.contains(where: { $0.id == "demand" }) {
                actions.insert(SuggestedAction(id: "demand", title: "Generate Demand Letter", section: .documents), at: 0)
            }
            if !actions.contains(where: { $0.id == "complaint" }) {
                actions.append(SuggestedAction(id: "complaint", title: "Draft Complaint", section: .documents))
            }
        }
        var seen = Set<String>()
        return Array(actions.filter { seen.insert($0.id).inserted }.prefix(6))
    }

    private func actionIcon(for section: CaseWorkspaceSection) -> String {
        switch section {
        case .documents: return "doc.text.fill"
        case .evidence: return "folder.fill.badge.plus"
        case .recordings: return "mic.fill"
        default: return "arrow.right.circle.fill"
        }
    }
}

struct CaseDashboardView: View {
    let analysis: CaseAnalysis
    var deadlines: [LegalDeadline] = []
    var strategy: LitigationStrategy? = nil
    var confidence: CaseConfidence? = nil
    var onSuggestedAction: ((CaseWorkspaceSection) -> Void)? = nil
    /// When false, omit the Suggested Actions section (e.g. when shown as its own card).
    var showSuggestedActions: Bool = true
    /// When set, show this icon and title at the top of the card (for card-based workspace layout).
    var headerIcon: String? = nil
    var headerTitle: String? = nil
    /// When false and strategy is present, show upgrade CTA instead of strategy content (advanced litigation strategy is premium).
    var hasFullAccess: Bool = true
    /// Called when user taps upgrade for advanced strategy. Parent should show upgrade prompt sheet.
    var onUpgradeRequested: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let icon = headerIcon, let title = headerTitle {
                WorkspaceCardHeader(icon: icon, title: title)
            }
            if showSuggestedActions {
                sectionBlock("AI SUGGESTED ACTIONS") {
                    suggestedActionsSection
                }
            }
            sectionBlock("CASE SUMMARY") {
                sectionBody(analysis.summary)
            }

            sectionBlock("POTENTIAL CLAIMS") {
                checklistItems(analysis.claims)
            }

            sectionBlock("ESTIMATED DAMAGES") {
                sectionBody(estimatedDamagesDisplay)
            }

            sectionBlock("EVIDENCE NEEDED") {
                checklistItems(analysis.evidenceNeeded)
            }

            sectionBlock("TIMELINE OF EVENTS") {
                if analysis.timeline.isEmpty {
                    sectionBody("No timeline events extracted.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(analysis.timeline) { event in
                            HStack(alignment: .top, spacing: 8) {
                                if let date = event.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(LuxuryTheme.bodyFont(size: 12))
                                        .foregroundColor(AppColors.textPrimary)
                                        .frame(width: 70, alignment: .leading)
                                }
                                Text(event.description)
                                    .font(LuxuryTheme.bodyFont(size: 15))
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            sectionBlock("NEXT STEPS") {
                checklistItems(analysis.nextSteps)
            }

            sectionBlock("DOCUMENTS TO PREPARE") {
                checklistItems(analysis.documents)
            }

            sectionBlock("WHERE TO FILE") {
                checklistItems(analysis.filingLocations)
            }

            sectionBlock("DEADLINES") {
                if deadlines.isEmpty {
                    sectionBody("None listed.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(deadlines) { d in
                            HStack(alignment: .top, spacing: 8) {
                                if let due = d.dueDate {
                                    Text(due.formatted(date: .abbreviated, time: .omitted))
                                        .font(LuxuryTheme.bodyFont(size: 12))
                                        .foregroundColor(AppColors.textPrimary)
                                        .frame(width: 70, alignment: .leading)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title)
                                        .font(LuxuryTheme.bodyFont(size: 15))
                                        .foregroundColor(AppColors.textPrimary)
                                    if let notes = d.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(LuxuryTheme.bodyFont(size: 13))
                                            .foregroundColor(AppColors.textPrimary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if let confidence = confidence {
                caseStrengthSection(confidence)
            }

            if let strategy = strategy {
                if hasFullAccess {
                    strategySection(strategy)
                } else {
                    advancedStrategyUpgradeCTA
                }
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    /// Case Strength section: Claim Strength %, Evidence Strength, Settlement Probability, Litigation Risk. Shown when confidence is non-nil.
    private func caseStrengthSection(_ confidence: CaseConfidence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("CASE STRENGTH")
                .font(LuxuryTheme.sectionFont(size: 14))
                .foregroundColor(AppColors.textPrimary)

            confidenceRow(label: "Claim Strength", value: "\(confidence.claimStrength)%")
            confidenceRow(label: "Evidence Strength", value: confidence.evidenceStrength)
            confidenceRow(label: "Settlement Probability", value: confidence.settlementProbability)
            confidenceRow(label: "Litigation Risk", value: confidence.litigationRisk)
        }
    }

    private func confidenceRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
            Text(value)
                .font(LuxuryTheme.bodyFont(size: 15))
                .foregroundColor(AppColors.textPrimary)
        }
    }

    /// Shown when strategy exists but user does not have premium (advanced litigation strategy is a premium feature).
    private var advancedStrategyUpgradeCTA: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("STRATEGY")
                .font(LuxuryTheme.sectionFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
            Text("Advanced litigation strategy is available with a premium subscription. Upgrade to unlock strategy insights and evidence gap analysis.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
            Button("Upgrade to view strategy") {
                onUpgradeRequested?()
            }
            .font(LuxuryTheme.buttonFont(size: 14))
            .foregroundColor(AppColors.textPrimary)
        }
    }

    /// Strategy section: Legal Theories, Strengths, Weaknesses, Evidence Gaps, Opposing Arguments, Settlement Range, Litigation Plan. Shown below Case Analysis when strategy is non-nil.
    private func strategySection(_ strategy: LitigationStrategy) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("STRATEGY")
                .font(LuxuryTheme.sectionFont(size: 14))
                .foregroundColor(AppColors.textPrimary)

            sectionBlock("Legal Theories") {
                checklistItems(strategy.legalTheories)
            }
            sectionBlock("Strengths") {
                checklistItems(strategy.strengths)
            }
            sectionBlock("Weaknesses") {
                checklistItems(strategy.weaknesses)
            }
            sectionBlock("Evidence Gaps") {
                checklistItems(strategy.evidenceGaps)
            }
            sectionBlock("Opposing Arguments") {
                checklistItems(strategy.opposingArguments)
            }
            sectionBlock("Settlement Range") {
                sectionBody(strategy.settlementRange ?? "—")
            }
            sectionBlock("Litigation Plan") {
                checklistItems(strategy.litigationPlan)
            }
        }
    }

    /// Estimated damages always shown and must include "(depending on further evidence)".
    private var estimatedDamagesDisplay: String {
        let base = analysis.estimatedDamages.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return "Depending on further evidence."
        }
        return "\(base) (depending on further evidence)"
    }

    private func sectionBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            content()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(LuxuryTheme.sectionFont(size: 12))
            .foregroundColor(AppColors.textPrimary)
    }

    private func sectionBody(_ text: String) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(LuxuryTheme.bodyFont(size: 15))
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func checklistItems(_ items: [String]) -> some View {
        Group {
            if items.isEmpty {
                sectionBody("None listed.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(AppTypography.body)
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

    // MARK: - AI Suggested Actions (from CaseAnalysis)

    private var suggestedActions: [SuggestedAction] {
        var actions: [SuggestedAction] = []
        let docLower = analysis.documents.map { $0.lowercased() }.joined(separator: " ")
        let nextLower = analysis.nextSteps.map { $0.lowercased() }.joined(separator: " ")
        let evidenceLower = analysis.evidenceNeeded.map { $0.lowercased() }.joined(separator: " ")

        if docLower.contains("demand letter") || nextLower.contains("demand") {
            actions.append(SuggestedAction(id: "demand", title: "Generate Demand Letter", section: .documents))
        }
        if !analysis.evidenceNeeded.isEmpty || evidenceLower.contains("evidence") {
            actions.append(SuggestedAction(id: "evidence", title: "Upload Evidence", section: .evidence))
        }
        actions.append(SuggestedAction(id: "witness", title: "Add Witness Statement", section: .recordings))
        if docLower.contains("complaint") || nextLower.contains("file") || nextLower.contains("complaint") {
            actions.append(SuggestedAction(id: "complaint", title: "Draft Complaint", section: .documents))
        }
        if actions.count < 2 {
            if !actions.contains(where: { $0.id == "demand" }) {
                actions.insert(SuggestedAction(id: "demand", title: "Generate Demand Letter", section: .documents), at: 0)
            }
            if !actions.contains(where: { $0.id == "complaint" }) {
                actions.append(SuggestedAction(id: "complaint", title: "Draft Complaint", section: .documents))
            }
        }
        var seen = Set<String>()
        return Array(actions.filter { seen.insert($0.id).inserted }.prefix(6))
    }

    @ViewBuilder
    private var suggestedActionsSection: some View {
        let actions = suggestedActions
        if actions.isEmpty {
            sectionBody("No suggested actions right now.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(actions) { action in
                    Button {
                        onSuggestedAction?(action.section)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconName(for: action.section))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.primary)
                            Text(action.title)
                                .font(LuxuryTheme.bodyFont(size: 15))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(LuxuryTheme.surfaceCard)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func iconName(for section: CaseWorkspaceSection) -> String {
        switch section {
        case .documents: return "doc.text.fill"
        case .evidence: return "folder.fill.badge.plus"
        case .recordings: return "mic.fill"
        default: return "arrow.right.circle.fill"
        }
    }
}
