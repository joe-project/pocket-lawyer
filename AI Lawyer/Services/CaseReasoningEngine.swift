import Foundation

/// Full case context sent to the AI so it reasons over the entire case: messages, voice/recording transcripts, evidence summaries, timeline, and prior analysis.
struct FullCaseContext {
    var messages: [Message]
    var timelineEvents: [TimelineEvent]
    var evidenceSummaries: [String]
    /// Transcript text from recording files (e.g. Voice Stories, Witness Statements).
    var recordingTranscripts: [String]
    var priorAnalysis: CaseAnalysis?
}

/// Produces an updated case analysis from full case context (messages, transcripts, evidence, timeline, prior analysis) and suggests or generates relevant legal documents when analysis changes (e.g. claim-based: Demand Letter, Civil Complaint, Evidence Checklist). Creates new versions instead of replacing existing documents.
struct CaseReasoningEngine {
    private let aiEngine: AIEngine
    private let documentEngine: DocumentEngine

    init(aiEngine: AIEngine = .shared, documentEngine: DocumentEngine? = nil) {
        self.aiEngine = aiEngine
        self.documentEngine = documentEngine ?? DocumentEngine(aiEngine: aiEngine)
    }

    // MARK: - Claim → suggested document types (e.g. wrongful eviction → Demand Letter, Civil Complaint, Evidence Checklist)
    private static let claimToSuggestedDocuments: [(keywords: Set<String>, documents: [String])] = [
        (["wrongful eviction", "eviction", "illegal lockout"], ["Demand Letter", "Civil Complaint", "Evidence Checklist"]),
        (["breach of contract", "contract"], ["Demand Letter", "Civil Complaint", "Evidence Checklist"]),
        (["discrimination", "wrongful termination", "employment"], ["Demand Letter", "EEOC Charge", "Evidence Checklist"]),
        (["personal injury", "negligence", "accident"], ["Demand Letter", "Civil Complaint", "Evidence Checklist"]),
        (["landlord", "tenant", "housing"], ["Demand Letter", "Civil Complaint", "Evidence Checklist"]),
    ]

    /// Builds a single text blob from full case context for the AI. Order: prior analysis → timeline → evidence → recordings → conversation.
    private static func buildFullContextText(_ context: FullCaseContext) -> String {
        var sections: [String] = []

        if let prior = context.priorAnalysis, !prior.summary.isEmpty {
            sections.append("--- PRIOR CASE ANALYSIS ---")
            sections.append("Summary: \(prior.summary)")
            if !prior.claims.isEmpty { sections.append("Potential claims: \(prior.claims.joined(separator: "; "))") }
            if !prior.estimatedDamages.isEmpty { sections.append("Estimated damages: \(prior.estimatedDamages)") }
            if !prior.evidenceNeeded.isEmpty { sections.append("Evidence needed: \(prior.evidenceNeeded.joined(separator: "; "))") }
            if !prior.timeline.isEmpty { sections.append("Timeline: " + prior.timeline.map { $0.description }.joined(separator: " | ")) }
            if !prior.nextSteps.isEmpty { sections.append("Next steps: \(prior.nextSteps.joined(separator: "; "))") }
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

        sections.append("--- FULL CONVERSATION ---")
        for msg in context.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
            let role = msg.role == "user" ? "User" : "Assistant"
            sections.append("\(role): \(msg.content)")
        }

        return sections.joined(separator: "\n")
    }

    /// Sends the structured case context through `AIEngine` and returns a structured CaseAnalysis. Use CaseContextBuilder to build the context.
    func updateCaseAnalysis(context: CaseContext, caseId: UUID) async -> CaseAnalysis? {
        let fullText = CaseContextBuilder.promptText(for: context)
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        do {
            return try await aiEngine.analyzeCase(context: context)
        } catch {
            print("CaseReasoningEngine: update failed", error)
            return nil
        }
    }

    /// Legacy: accepts FullCaseContext for compatibility. Prefer building CaseContext with CaseContextBuilder and calling updateCaseAnalysis(context: CaseContext, caseId:).
    func updateCaseAnalysis(context: FullCaseContext, caseId: UUID) async -> CaseAnalysis? {
        let caseContext = CaseContext(
            caseSummary: context.priorAnalysis?.summary ?? "",
            messages: context.messages,
            timelineEvents: context.timelineEvents,
            evidenceSummaries: context.evidenceSummaries,
            recordingTranscripts: context.recordingTranscripts,
            existingCaseAnalysis: context.priorAnalysis,
            litigationStrategy: nil
        )
        return await updateCaseAnalysis(context: caseContext, caseId: caseId)
    }

    /// Returns suggested document types to generate based on the case analysis (e.g. when a wrongful eviction claim is detected → Demand Letter, Civil Complaint, Evidence Checklist). Use this to drive UI suggestions or to pass into `generateSuggestedDocuments`.
    func suggestedDocumentTypes(for analysis: CaseAnalysis) -> [String] {
        let claimText = analysis.claims.map { $0.lowercased() }.joined(separator: " ")
        var suggested: Set<String> = []
        for (keywords, documents) in Self.claimToSuggestedDocuments {
            if keywords.contains(where: { claimText.contains($0) }) {
                suggested.formUnion(documents)
            }
        }
        // If no claim matched, suggest common set so user still gets options
        if suggested.isEmpty {
            suggested = ["Demand Letter", "Evidence Checklist"]
        }
        return suggested.sorted()
    }

    /// Generates and saves new versions of suggested documents for the case (based on claims). Does not replace existing documents; each is stored with an incremented version (e.g. "Demand Letter v2"). Returns generated CaseDocuments; skips types that fail (e.g. network error).
    func generateSuggestedDocuments(
        caseId: UUID,
        caseAnalysis: CaseAnalysis,
        caseTreeViewModel: CaseTreeViewModel
    ) async -> [CaseDocument] {
        let types = suggestedDocumentTypes(for: caseAnalysis)
        let existingFiles = caseTreeViewModel.files(for: caseId, subfolder: .documents)
        var generated: [CaseDocument] = []
        for documentType in types {
            let existingVersion = documentEngine.nextVersionNumber(for: documentType, existingFiles: existingFiles)
            do {
                let doc = try await documentEngine.generateDocument(
                    caseAnalysis: caseAnalysis,
                    documentType: documentType,
                    existingVersion: existingVersion
                )
                if documentEngine.saveToCase(caseId: caseId, document: doc, using: caseTreeViewModel) != nil {
                    generated.append(doc)
                }
            } catch {
                print("CaseReasoningEngine: failed to generate \(documentType)", error)
            }
        }
        return generated
    }
}
