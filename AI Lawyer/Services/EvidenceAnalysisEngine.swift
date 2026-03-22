import Foundation

/// Analyzes uploaded evidence documents and extracts legal information: violations, timeline events, damages, deadlines, missing evidence.
/// When a document is uploaded to Evidence (with text content), the app runs: extract text → `AIEngine` → EvidenceAnalysis →
/// attach violations, timeline events, and deadlines to the case → update CaseReasoningEngine (refresh case analysis).
final class EvidenceAnalysisEngine {
    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    // MARK: - Analyze document text

    /// Sends document text to the AI and returns a structured EvidenceAnalysis. Call this when the user uploads a PDF, image, or text document (after extracting text).
    func analyze(documentText: String) async throws -> EvidenceAnalysis {
        try await aiEngine.analyzeEvidenceDocument(documentText)
    }

    /// Parses JSON from the AI response into EvidenceAnalysis. Strips markdown code blocks if present. Used by `AIEngine`.
    static func parseModelResponse(_ response: String) throws -> EvidenceAnalysis {
        let jsonString = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            throw EvidenceAnalysisError.invalidResponse("Could not encode response as UTF-8")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                throw DecodingError.valueNotFound(Date.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected date string or null"))
            }
            let str = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.fullWithOptionalFractionalSeconds.date(from: str)
                ?? ISO8601DateFormatter.full.date(from: str) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid date string: \(str)"))
            }
            return date
        }

        let dto = try decoder.decode(EvidenceAnalysisDTO.self, from: data)
        return dto.toEvidenceAnalysis()
    }

    // MARK: - Apply results to case

    /// Attaches analysis results to the case: adds timeline events and deadlines to the case, and returns an updated CaseAnalysis if you pass the current one (for merging new information).
    /// - Parameters:
    ///   - evidenceAnalysis: Result from `analyze(documentText:)`.
    ///   - caseId: Case to attach to.
    ///   - caseTreeViewModel: Used to add timeline events and deadlines.
    ///   - currentAnalysis: Optional current CaseAnalysis to merge new info into; if nil, a new CaseAnalysis is built from the evidence only.
    /// - Returns: Updated or new CaseAnalysis to set on the case (e.g. via ConversationManager or ChatViewModel).
    @MainActor
    func apply(
        _ evidenceAnalysis: EvidenceAnalysis,
        toCaseId caseId: UUID,
        caseTreeViewModel: CaseTreeViewModel,
        currentAnalysis: CaseAnalysis?
    ) -> CaseAnalysis {
        // 1. Add timeline events to case timeline
        for event in evidenceAnalysis.timelineEvents {
            let timelineEvent = TimelineEvent(
                kind: .response,
                title: event.description,
                summary: nil,
                createdAt: event.date ?? Date(),
                documentId: nil,
                subfolder: .evidence
            )
            caseTreeViewModel.addTimelineEvent(timelineEvent, caseId: caseId)
        }

        // 2. Add deadlines to case
        caseTreeViewModel.addDeadlines(evidenceAnalysis.deadlines, caseId: caseId)

        // 3. Merge into CaseAnalysis
        return mergeEvidenceIntoCaseAnalysis(evidenceAnalysis, current: currentAnalysis)
    }

    /// Merges evidence analysis into existing CaseAnalysis (or creates one): summary, claims from violations, damages, timeline, evidence needed from missingEvidence.
    private func mergeEvidenceIntoCaseAnalysis(_ evidence: EvidenceAnalysis, current: CaseAnalysis?) -> CaseAnalysis {
        if let current = current {
            return CaseAnalysis(
                summary: current.summary.isEmpty ? evidence.summary : current.summary + "\n\n[Evidence] " + evidence.summary,
                claims: mergeDistinct(current.claims, evidence.violations),
                estimatedDamages: evidence.damages?.isEmpty == false ? evidence.damages! : current.estimatedDamages,
                evidenceNeeded: mergeDistinct(current.evidenceNeeded, evidence.missingEvidence ?? []),
                timeline: current.timeline + evidence.timelineEvents,
                nextSteps: current.nextSteps,
                documents: current.documents,
                filingLocations: current.filingLocations
            )
        }
        return CaseAnalysis(
            summary: evidence.summary,
            claims: evidence.violations,
            estimatedDamages: evidence.damages ?? "To be assessed",
            evidenceNeeded: evidence.missingEvidence ?? [],
            timeline: evidence.timelineEvents,
            nextSteps: [],
            documents: [],
            filingLocations: []
        )
    }

    private func mergeDistinct(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set(a.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        var result = a
        for item in b {
            let t = item.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if seen.insert(t.lowercased()).inserted {
                result.append(t)
            }
        }
        return result
    }
}

// MARK: - DTOs for JSON decoding (AI may omit ids or use string dates)

private struct EvidenceAnalysisDTO: Decodable {
    let summary: String
    let violations: [String]
    let damages: String?
    let timelineEvents: [TimelineEventDTO]
    let deadlines: [LegalDeadlineDTO]
    let missingEvidence: [String]?

    struct TimelineEventDTO: Decodable {
        let date: String?
        let description: String
    }

    struct LegalDeadlineDTO: Decodable {
        let title: String
        let dueDate: String?
        let notes: String?
    }

    func toEvidenceAnalysis() -> EvidenceAnalysis {
        let events = timelineEvents.map { dto in
            CaseTimelineEvent(
                id: UUID(),
                date: parseISO8601(dto.date),
                description: dto.description
            )
        }
        let deadlines = deadlines.map { dto in
            LegalDeadline(
                id: UUID(),
                title: dto.title,
                dueDate: parseISO8601(dto.dueDate),
                notes: dto.notes
            )
        }
        return EvidenceAnalysis(
            summary: summary,
            violations: violations,
            damages: damages,
            timelineEvents: events,
            deadlines: deadlines,
            missingEvidence: missingEvidence
        )
    }
}

private func parseISO8601(_ string: String?) -> Date? {
    guard let s = string?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    return ISO8601DateFormatter.fullWithOptionalFractionalSeconds.date(from: s)
        ?? ISO8601DateFormatter.full.date(from: s)
}

private extension ISO8601DateFormatter {
    static let full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
    static let fullWithOptionalFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

enum EvidenceAnalysisError: LocalizedError {
    case emptyDocument
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "Document text is empty."
        case .invalidResponse(let msg):
            return "Could not parse evidence analysis: \(msg)"
        }
    }
}
