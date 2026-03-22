import Foundation

/// Recommendation to connect with a licensed attorney for a case. Shown when the system detects a potentially strong legal case (e.g. high damages, strong evidence, litigation likely).
struct AttorneyReferral: Identifiable {
    let id: UUID
    let caseId: UUID
    let recommendation: String

    init(id: UUID = UUID(), caseId: UUID, recommendation: String) {
        self.id = id
        self.caseId = caseId
        self.recommendation = recommendation
    }
}

/// Suggests connecting with a licensed attorney when the AI detects a potentially strong legal case. Triggers include high damages estimate, strong evidence, or litigation likely.
final class AttorneyReferralEngine {

    /// Default recommendation text shown with the "Connect with Attorney" action.
    static let defaultRecommendation = "You may benefit from speaking with a licensed attorney about this case."

    /// Title for the referral action button in the UI.
    static let connectButtonTitle = "Connect with Attorney"

    /// Determines whether to show an attorney referral for this case. Returns an `AttorneyReferral` when triggers are met (high damages, strong evidence, or litigation likely); otherwise nil.
    /// - Parameters:
    ///   - caseId: The case id.
    ///   - analysis: Current case analysis (claims, damages, next steps, etc.).
    ///   - evidenceCount: Number of evidence items (e.g. uploaded documents) for the case.
    func recommendReferral(caseId: UUID, analysis: CaseAnalysis, evidenceCount: Int) -> AttorneyReferral? {
        let highDamages = Self.isHighDamages(analysis.estimatedDamages)
        let strongEvidence = Self.isStrongEvidence(evidenceCount: evidenceCount, analysis: analysis)
        let litigationLikely = Self.isLitigationLikely(analysis: analysis)

        guard highDamages || strongEvidence || litigationLikely else { return nil }

        return AttorneyReferral(
            caseId: caseId,
            recommendation: Self.defaultRecommendation
        )
    }

    // MARK: - Triggers

    private static func isHighDamages(_ estimatedDamages: String) -> Bool {
        let trimmed = estimatedDamages.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return false }
        // Dollar amounts: look for $ followed by digits (e.g. $50,000 or $50k)
        if let range = trimmed.range(of: "\\$[\\d,]+", options: .regularExpression) {
            let match = String(trimmed[range])
            let digits = match.filter(\.isNumber)
            if let value = Int(digits), value >= 10_000 { return true }
        }
        if trimmed.contains("k") || trimmed.contains("million") || trimmed.contains("substantial") || trimmed.contains("significant") || trimmed.contains("high") {
            return true
        }
        return false
    }

    private static func isStrongEvidence(evidenceCount: Int, analysis: CaseAnalysis) -> Bool {
        if evidenceCount >= 3 { return true }
        if evidenceCount >= 1 && !analysis.claims.isEmpty { return true }
        return false
    }

    private static func isLitigationLikely(analysis: CaseAnalysis) -> Bool {
        let combined = [
            analysis.summary,
            analysis.nextSteps.joined(separator: " "),
            analysis.documents.joined(separator: " "),
            analysis.filingLocations.joined(separator: " ")
        ].joined(separator: " ").lowercased()
        let markers = ["file a complaint", "file complaint", "sue", "lawsuit", "litigation", "in court", "file in court", "civil complaint", "filing a lawsuit"]
        return markers.contains { combined.contains($0) }
    }
}
