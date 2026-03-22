import Foundation

/// Represents a potential litigation funding opportunity for a case.
struct FundingOpportunity: Identifiable {
    let id: UUID
    let caseId: UUID
    let message: String

    init(id: UUID = UUID(), caseId: UUID, message: String) {
        self.id = id
        self.caseId = caseId
        self.message = message
    }
}

/// Detects cases that may qualify for litigation funding based on high damages estimate, strong evidence indicators, and clear legal claims.
final class CaseFundingEngine {

    /// Default message when the case appears to qualify for funding.
    static let defaultFundingMessage = "Your case may qualify for litigation funding."

    /// Evaluates whether the case may qualify for litigation funding. Returns a `FundingOpportunity` when criteria are met (e.g. high damages, strong evidence, clear claims); otherwise nil.
    /// - Parameters:
    ///   - caseId: The case id to attach to the opportunity.
    ///   - caseAnalysis: Current case analysis (damages, claims, evidence needed, timeline).
    func evaluate(caseId: UUID, caseAnalysis: CaseAnalysis) -> FundingOpportunity? {
        let hasHighDamages = isHighDamages(caseAnalysis.estimatedDamages)
        let hasClearClaims = !caseAnalysis.claims.isEmpty
        let hasStrongEvidenceIndicators = hasStrongEvidenceIndicators(caseAnalysis)

        guard hasHighDamages || (hasClearClaims && hasStrongEvidenceIndicators) else {
            return nil
        }

        return FundingOpportunity(
            caseId: caseId,
            message: Self.defaultFundingMessage
        )
    }

    // MARK: - Criteria

    private func isHighDamages(_ estimatedDamages: String) -> Bool {
        let trimmed = estimatedDamages.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.contains("$") { return true }
        let lower = trimmed.lowercased()
        if lower.contains("significant") || lower.contains("substantial") || lower.contains("high") || lower.contains("million") || lower.contains("k") {
            return true
        }
        return false
    }

    private func hasStrongEvidenceIndicators(_ analysis: CaseAnalysis) -> Bool {
        if analysis.timeline.count >= 2 { return true }
        if !analysis.evidenceNeeded.isEmpty && !analysis.claims.isEmpty { return true }
        return false
    }
}
