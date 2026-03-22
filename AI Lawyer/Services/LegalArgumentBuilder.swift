import Foundation

// MARK: - Model

/// A structured legal argument in IRAC form for a single claim.
struct LegalArgument: Codable {
    let claim: String
    let legalRule: String
    let facts: String
    let evidence: [String]
    let conclusion: String
}

// MARK: - Engine

/// Constructs structured legal arguments (IRAC) for each claim in a case.
final class LegalArgumentBuilder {
    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    /// Builds legal arguments for each claim using case analysis, evidence summaries, and timeline.
    func buildArguments(
        caseAnalysis: CaseAnalysis,
        evidence: [EvidenceAnalysis],
        timeline: [TimelineEvent]
    ) async throws -> [LegalArgument] {
        let claimsText = caseAnalysis.claims.isEmpty ? "(none)" : caseAnalysis.claims.joined(separator: ", ")
        let evidenceSummaries = evidence.isEmpty ? "(none)" : evidence.map(\.summary).joined(separator: "\n")
        let timelineLines = timeline.map { event in
            let part = event.summary.map { "\(event.title): \($0)" } ?? event.title
            return part
        }
        let timelineText = timelineLines.isEmpty ? "(none)" : timelineLines.joined(separator: "\n")

        let prompt = """
        Construct structured legal arguments using the IRAC format.

        Case summary:
        \(caseAnalysis.summary)

        Claims:
        \(claimsText)

        Evidence summaries:
        \(evidenceSummaries)

        Timeline:
        \(timelineText)

        For each claim provide:

        CLAIM
        LEGAL RULE
        FACTS
        EVIDENCE
        CONCLUSION

        Conclusions should include "depending on further evidence".

        Respond with a JSON array only. Each object: {"claim":"...","legalRule":"...","facts":"...","evidence":["..."],"conclusion":"..."}. Use no markdown or extra text.
        """

        let chatMessage = ChatMessage(sender: .user, text: prompt)
        let (response, _, _) = try await aiEngine.chat(messages: [chatMessage])
        return LegalArgumentParser.parse(response)
    }
}
