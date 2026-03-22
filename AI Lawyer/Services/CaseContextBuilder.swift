import Foundation

/// Structured context for AI reasoning: all relevant case data passed to `AIEngine` when reasoning updates occur.
struct CaseContext {
    var caseSummary: String
    var messages: [Message]
    var timelineEvents: [TimelineEvent]
    var evidenceSummaries: [String]
    /// Transcript text from recording files (e.g. Voice Stories, Witness Statements).
    var recordingTranscripts: [String]
    var existingCaseAnalysis: CaseAnalysis?
    var litigationStrategy: LitigationStrategy?
    /// Optional legal references (citations and summaries from CourtListener, GovInfo, LII) to include so the AI can cite them.
    var legalReferencesAppendix: String?
    /// When set, this memory is included in the prompt instead of the full conversation so the AI does not need the entire message history.
    var caseMemory: CaseMemory?
}

/// Builds a CaseContext from case data and renders it to a prompt string for `AIEngine`.
enum CaseContextBuilder {

    /// Builds a structured context object for AI reasoning. Pass the result to CaseReasoningEngine and use `promptText(for:)` when calling `AIEngine`.
    /// When caseMemory is non-nil, the prompt uses it instead of the full conversation.
    static func build(
        caseId: UUID,
        messages: [Message],
        timelineEvents: [TimelineEvent],
        evidenceSummaries: [String],
        recordingTranscripts: [String],
        caseAnalysis: CaseAnalysis?,
        litigationStrategy: LitigationStrategy?,
        legalReferencesAppendix: String? = nil,
        caseMemory: CaseMemory? = nil
    ) -> CaseContext {
        let caseSummary = caseAnalysis?.summary ?? ""
        return CaseContext(
            caseSummary: caseSummary,
            messages: messages,
            timelineEvents: timelineEvents,
            evidenceSummaries: evidenceSummaries,
            recordingTranscripts: recordingTranscripts,
            existingCaseAnalysis: caseAnalysis,
            litigationStrategy: litigationStrategy,
            legalReferencesAppendix: legalReferencesAppendix,
            caseMemory: caseMemory
        )
    }

    /// Renders the context to a single text blob for the AI prompt. Include this in the user message when calling `AIEngine` for reasoning updates.
    static func promptText(for context: CaseContext) -> String {
        var sections: [String] = []

        if !context.caseSummary.isEmpty {
            sections.append("--- CASE SUMMARY ---")
            sections.append(context.caseSummary)
            sections.append("")
        }

        if let prior = context.existingCaseAnalysis {
            sections.append("--- EXISTING CASE ANALYSIS ---")
            sections.append("Summary: \(prior.summary)")
            if !prior.claims.isEmpty { sections.append("Potential claims: \(prior.claims.joined(separator: "; "))") }
            if !prior.estimatedDamages.isEmpty { sections.append("Estimated damages: \(prior.estimatedDamages)") }
            if !prior.evidenceNeeded.isEmpty { sections.append("Evidence needed: \(prior.evidenceNeeded.joined(separator: "; "))") }
            if !prior.timeline.isEmpty { sections.append("Timeline: " + prior.timeline.map { $0.description }.joined(separator: " | ")) }
            if !prior.nextSteps.isEmpty { sections.append("Next steps: \(prior.nextSteps.joined(separator: "; "))") }
            sections.append("")
        }

        if let refs = context.legalReferencesAppendix, !refs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(refs)
            sections.append("")
        }

        if let strategy = context.litigationStrategy {
            sections.append("--- LITIGATION STRATEGY ---")
            if !strategy.legalTheories.isEmpty { sections.append("Legal theories: \(strategy.legalTheories.joined(separator: "; "))") }
            if !strategy.strengths.isEmpty { sections.append("Strengths: \(strategy.strengths.joined(separator: "; "))") }
            if !strategy.weaknesses.isEmpty { sections.append("Weaknesses: \(strategy.weaknesses.joined(separator: "; "))") }
            if !strategy.evidenceGaps.isEmpty { sections.append("Evidence gaps: \(strategy.evidenceGaps.joined(separator: "; "))") }
            if !strategy.opposingArguments.isEmpty { sections.append("Opposing arguments: \(strategy.opposingArguments.joined(separator: "; "))") }
            if let range = strategy.settlementRange { sections.append("Settlement range: \(range)") }
            if !strategy.litigationPlan.isEmpty { sections.append("Litigation plan: \(strategy.litigationPlan.joined(separator: "; "))") }
            sections.append("")
        }

        if !context.timelineEvents.isEmpty {
            sections.append("--- TIMELINE EVENTS ---")
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for event in context.timelineEvents.sorted(by: { $0.createdAt < $1.createdAt }) {
                let dateStr = formatter.string(from: event.createdAt)
                let line = "\(dateStr) – \(event.title)" + (event.summary.map { " (\($0))" } ?? "")
                sections.append(line)
            }
            sections.append("")
        }

        if !context.evidenceSummaries.isEmpty {
            sections.append("--- EVIDENCE SUMMARIES ---")
            sections.append(contentsOf: context.evidenceSummaries)
            sections.append("")
        }

        if !context.recordingTranscripts.isEmpty {
            sections.append("--- VOICE / RECORDING TRANSCRIPTS ---")
            for (i, transcript) in context.recordingTranscripts.enumerated() {
                sections.append("[Recording \(i + 1)] \(transcript)")
            }
            sections.append("")
        }

        if let memory = context.caseMemory {
            sections.append("--- CASE MEMORY ---")
            sections.append(formatCaseMemory(memory))
            sections.append("")
        } else {
            sections.append("--- FULL CONVERSATION ---")
            for msg in context.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
                let role = msg.role == "user" ? "User" : "Assistant"
                sections.append("\(role): \(msg.content)")
            }
        }

        return sections.joined(separator: "\n")
    }

    /// Renders CaseMemory to a single block for the prompt.
    private static func formatCaseMemory(_ memory: CaseMemory) -> String {
        var parts: [String] = []
        if !memory.people.isEmpty {
            parts.append("People: " + memory.people.joined(separator: "; "))
        }
        if !memory.events.isEmpty {
            parts.append("Events: " + memory.events.joined(separator: "; "))
        }
        if !memory.evidence.isEmpty {
            parts.append("Evidence: " + memory.evidence.joined(separator: "; "))
        }
        if !memory.claims.isEmpty {
            parts.append("Claims: " + memory.claims.joined(separator: "; "))
        }
        if let d = memory.damagesEstimate, !d.isEmpty {
            parts.append("Damages estimate: \(d)")
        }
        return parts.isEmpty ? "(none yet)" : parts.joined(separator: "\n")
    }

    /// Stable fingerprint for CaseMemory so cache signature changes when memory content changes.
    static func memoryFingerprint(_ memory: CaseMemory?) -> String? {
        guard let memory = memory else { return nil }
        let parts = [
            memory.people.joined(separator: "|"),
            memory.events.joined(separator: "|"),
            memory.evidence.joined(separator: "|"),
            memory.claims.joined(separator: "|"),
            memory.damagesEstimate ?? ""
        ]
        return parts.joined(separator: ";")
    }
}
