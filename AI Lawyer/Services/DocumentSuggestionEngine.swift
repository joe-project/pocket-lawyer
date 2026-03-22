import Foundation

/// A suggested document to generate, with a user-facing message (e.g. "I can generate a demand letter for this case. Would you like me to create one?").
struct DocumentSuggestion {
    let documentType: String
    let message: String
}

/// Detects when a document should be generated during conversation by analyzing CaseAnalysis and optional conversation context. Produces a single, contextual suggestion with a ready-to-show message.
final class DocumentSuggestionEngine {

    /// Scenario keywords → (document type, message template). %@ = document type.
    private static let scenarioRules: [(keywords: Set<String>, documentType: String)] = [
        (["wrongful eviction", "eviction", "illegal lockout", "lockout", "landlord", "tenant", "housing"], "Demand Letter"),
        (["insurance denial", "insurance claim", "denied claim", "claim denied"], "Insurance Claim Letter"),
        (["contract dispute", "breach of contract", "contract breach", "breach of contract"], "Breach Notice"),
        (["discrimination", "wrongful termination", "employment"], "Demand Letter"),
        (["personal injury", "negligence", "accident"], "Demand Letter"),
        (["breach of contract", "contract"], "Breach Notice"),
    ]

    /// Message template; document type is inserted for "%@".
    private static let suggestionMessageTemplate = "I can generate a %@ for this case. Would you like me to create one?"

    /// Analyzes case analysis and optional conversation context and returns a single document suggestion with a user-facing message, or nil if none strongly suggested.
    /// - Parameters:
    ///   - analysis: Current case analysis (claims, summary).
    ///   - recentMessageText: Optional recent user/assistant text (e.g. last few messages joined) to improve context.
    /// - Returns: A suggestion with document type and message like "I can generate a demand letter for this case. Would you like me to create one?", or nil.
    func suggestDocument(
        analysis: CaseAnalysis,
        recentMessageText: String? = nil
    ) -> DocumentSuggestion? {
        let claimText = analysis.claims.map { $0.lowercased() }.joined(separator: " ")
        let summaryLower = analysis.summary.lowercased()
        let contextText = [claimText, summaryLower, recentMessageText?.lowercased() ?? ""].joined(separator: " ")

        for (keywords, documentType) in Self.scenarioRules {
            if keywords.contains(where: { contextText.contains($0) }) {
                let message = Self.suggestionMessageTemplate.replacingOccurrences(of: "%@", with: documentType.lowercased())
                return DocumentSuggestion(documentType: documentType, message: message)
            }
        }
        return nil
    }

    /// Returns all document types that match the case (for callers that want a list). Message is still generated for the first match via suggestDocument if you need the prompt.
    func suggestedDocumentTypes(for analysis: CaseAnalysis) -> [String] {
        let claimText = analysis.claims.map { $0.lowercased() }.joined(separator: " ")
        let summaryLower = analysis.summary.lowercased()
        let contextText = claimText + " " + summaryLower
        var types: Set<String> = []
        for (keywords, documentType) in Self.scenarioRules {
            if keywords.contains(where: { contextText.contains($0) }) {
                types.insert(documentType)
            }
        }
        return types.sorted()
    }
}
