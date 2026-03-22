import Foundation

/// Estimates how strong a case is based on case analysis, evidence, and timeline.
final class CaseConfidenceEngine {
    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    /// Evaluates case strength from analysis, evidence summaries, and timeline. Returns a CaseConfidence with claim strength (0-100), evidence strength, settlement probability, and litigation risk.
    func evaluate(
        analysis: CaseAnalysis,
        evidence: [EvidenceAnalysis],
        timeline: [CaseTimelineEvent]
    ) async throws -> CaseConfidence {
        try await aiEngine.evaluateConfidence(analysis: analysis, evidence: evidence, timeline: timeline)
    }
}
