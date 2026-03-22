import Foundation

// MARK: - Model

/// An alert produced by evidence verification: missing evidence, contradictions, or unclear timeline.
struct EvidenceAlert: Identifiable, Codable {
    let id: UUID
    let title: String
    let message: String

    init(id: UUID = UUID(), title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

// MARK: - Parser

enum EvidenceAlertParser {
    /// Parses the AI verification response into EvidenceAlert values. Expects JSON array or a bullet list; strips markdown/code fences.
    static func parse(_ response: String) -> [EvidenceAlert] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try JSON array: [{"title":"...","message":"..."}, ...]
        if let data = jsonString.data(using: .utf8),
           let dtos = try? JSONDecoder().decode([EvidenceAlertDTO].self, from: data) {
            return dtos.map { $0.toEvidenceAlert() }
        }

        // Fallback: bullet lines as single alert (e.g. "• Missing: X" or "1. Contradiction: Y")
        let lines = jsonString
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ($0.hasPrefix("•") || $0.hasPrefix("-") || $0.range(of: "^\\d+\\.", options: .regularExpression) != nil) }
        if !lines.isEmpty {
            let text = lines.joined(separator: "\n")
            return [EvidenceAlert(title: "Verification notes", message: text)]
        }

        return []
    }
}

private struct EvidenceAlertDTO: Decodable {
    let title: String?
    let message: String?

    func toEvidenceAlert() -> EvidenceAlert {
        EvidenceAlert(
            title: title ?? "Alert",
            message: message ?? ""
        )
    }
}

// MARK: - Engine

/// Improves case accuracy by checking for missing evidence and contradictions across case analysis, evidence, and timeline.
final class EvidenceVerificationEngine {
    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    /// Reviews the case for missing evidence, contradictions, and unclear timeline events; returns alerts.
    func verify(
        caseAnalysis: CaseAnalysis,
        evidence: [EvidenceAnalysis],
        timeline: [CaseTimelineEvent]
    ) async throws -> [EvidenceAlert] {
        let claimsText = caseAnalysis.claims.isEmpty ? "(none)" : caseAnalysis.claims.joined(separator: ", ")
        let evidenceSummaries = evidence.isEmpty ? "(none)" : evidence.map(\.summary).joined(separator: "\n")
        let timelineText = timeline.isEmpty ? "(none)" : timeline.map(\.description).joined(separator: "\n")

        let prompt = """
        Review this case for missing evidence or contradictions.

        Case summary:
        \(caseAnalysis.summary)

        Claims:
        \(claimsText)

        Evidence summaries:
        \(evidenceSummaries)

        Timeline events:
        \(timelineText)

        Identify:
        • missing evidence
        • contradictory facts
        • unclear timeline events

        Respond with a JSON array of alerts only. Each alert: {"title": "Short title", "message": "Explanation"}. Use no markdown or extra text.
        """

        let chatMessage = ChatMessage(sender: .user, text: prompt)
        let (response, _, _) = try await aiEngine.chat(messages: [chatMessage])
        return EvidenceAlertParser.parse(response)
    }
}
