import Foundation

/// Maintains a strategic legal analysis of the case that evolves as new information is added.
/// Callers should run strategy updates only when: new evidence is added, a new claim is detected, timeline events change, or damages estimates change—not on every chat message.
final class LitigationStrategyEngine {
    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    /// Updates the litigation strategy using current case analysis, evidence summaries, and timeline. Sends the full context through `AIEngine` and returns a parsed LitigationStrategy.
    func updateStrategy(
        caseAnalysis: CaseAnalysis,
        evidenceSummaries: [EvidenceAnalysis],
        timeline: [CaseTimelineEvent]
    ) async throws -> LitigationStrategy {
        try await aiEngine.updateLitigationStrategy(
            caseAnalysis: caseAnalysis,
            evidenceSummaries: evidenceSummaries,
            timeline: timeline
        )
    }
}
