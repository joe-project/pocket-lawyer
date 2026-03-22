import Foundation

// MARK: - Model

struct NextAction: Codable {
    let title: String
    let description: String
}

// MARK: - Engine

/// Analyzes the current case state and recommends the most important next action using the AI.
final class NextActionEngine {

    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    func recommendNextAction(
        caseAnalysis: CaseAnalysis,
        evidence: [EvidenceAnalysis],
        timeline: [CaseTimelineEvent]
    ) async throws -> NextAction {
        try await aiEngine.recommendNextAction(
            caseAnalysis: caseAnalysis,
            evidence: evidence,
            timeline: timeline
        )
    }
}
