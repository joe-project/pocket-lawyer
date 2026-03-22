import Foundation

/// Central orchestration for all AI calls. Only this type talks to `OpenAIService` (Worker proxy).
/// View models and feature engines depend on `AIEngine`, not on `OpenAIService` directly.
final class AIEngine: @unchecked Sendable {
    static let shared = AIEngine()

    private let openAIService: OpenAIService

    init(openAIService: OpenAIService = OpenAIService()) {
        self.openAIService = openAIService
    }

    // MARK: - Chat (intake, memory, documents-as-chat, verification, timeline, etc.)

    func chat(
        messages: [ChatMessage],
        previousMessages: [Message]? = nil
    ) async throws -> (String, Bool, [CaseTimelineEvent]) {
        try await openAIService.sendChat(messages: messages, previousMessages: previousMessages)
    }

    // MARK: - Case analysis (full case file → structured CaseAnalysis)

    func analyzeCase(context: CaseContext) async throws -> CaseAnalysis {
        let fullText = CaseContextBuilder.promptText(for: context)
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIEngineError.emptyContext
        }
        let response = try await openAIService.sendWithCustomPrompt(
            systemPrompt: Self.fullCaseAnalysisSystemPrompt,
            userMessage: "Analyze this complete case file and provide the structured legal analysis.\n\n\(fullText)"
        )
        return CaseAnalysisParser.parse(response)
    }

    // MARK: - Evidence document → JSON → EvidenceAnalysis

    func analyzeEvidenceDocument(_ documentText: String) async throws -> EvidenceAnalysis {
        let trimmed = documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EvidenceAnalysisError.emptyDocument
        }
        let response = try await openAIService.sendWithCustomPrompt(
            systemPrompt: Self.evidenceAnalysisSystemPrompt,
            userMessage: "Analyze the following evidence document:\n\n\(trimmed)"
        )
        return try EvidenceAnalysisEngine.parseModelResponse(response)
    }

    // MARK: - Next action

    func recommendNextAction(
        caseAnalysis: CaseAnalysis,
        evidence: [EvidenceAnalysis],
        timeline: [CaseTimelineEvent]
    ) async throws -> NextAction {
        let evidenceText = evidence.isEmpty
            ? "None yet."
            : evidence.map { $0.summary }.joined(separator: "\n")
        let timelineText = timeline.isEmpty
            ? "None yet."
            : timeline.map { $0.description }.joined(separator: "\n")

        let userMessage = """
        Review this legal case and recommend the most important next action.

        Case summary:
        \(caseAnalysis.summary)

        Claims:
        \(caseAnalysis.claims.joined(separator: ", "))

        Evidence:
        \(evidenceText)

        Timeline:
        \(timelineText)

        Provide:

        TITLE
        DESCRIPTION
        """

        let response = try await openAIService.sendWithCustomPrompt(
            systemPrompt: Self.nextActionSystemPrompt,
            userMessage: userMessage
        )
        return Self.parseNextAction(from: response)
    }

    // MARK: - Litigation strategy

    func updateLitigationStrategy(
        caseAnalysis: CaseAnalysis,
        evidenceSummaries: [EvidenceAnalysis],
        timeline: [CaseTimelineEvent]
    ) async throws -> LitigationStrategy {
        let evidenceText = evidenceSummaries.isEmpty
            ? "No evidence summaries yet."
            : evidenceSummaries.map { $0.summary }.joined(separator: "\n\n")
        let timelineText = timeline.isEmpty
            ? "No timeline events yet."
            : timeline.map { $0.description }.joined(separator: "\n")

        let userMessage = """
        Analyze this case and generate a litigation strategy.

        Case Summary:
        \(caseAnalysis.summary)

        Claims:
        \(caseAnalysis.claims.joined(separator: ", "))

        Timeline:
        \(timelineText)

        Evidence:
        \(evidenceText)

        Provide your analysis using the section headers: LEGAL THEORIES, STRENGTHS, WEAKNESSES, EVIDENCE GAPS, OPPOSING ARGUMENTS, SETTLEMENT RANGE, LITIGATION PLAN.
        """

        let response = try await openAIService.sendWithCustomPrompt(
            systemPrompt: Self.litigationStrategySystemPrompt,
            userMessage: userMessage
        )
        return LitigationStrategyParser.parse(response)
    }

    // MARK: - Case confidence

    func evaluateConfidence(
        analysis: CaseAnalysis,
        evidence: [EvidenceAnalysis],
        timeline: [CaseTimelineEvent]
    ) async throws -> CaseConfidence {
        let evidenceText = evidence.isEmpty
            ? "No evidence summaries yet."
            : evidence.map { $0.summary }.joined(separator: "\n\n")
        let timelineText = timeline.isEmpty
            ? "No timeline events yet."
            : timeline.map { $0.description }.joined(separator: "\n")

        let userMessage = """
        Evaluate the strength of this legal case.

        Case summary:
        \(analysis.summary)

        Claims:
        \(analysis.claims.joined(separator: ", "))

        Evidence summaries:
        \(evidenceText)

        Timeline:
        \(timelineText)

        Provide:

        CLAIM STRENGTH (percentage)
        EVIDENCE STRENGTH (Weak / Moderate / Strong)
        SETTLEMENT PROBABILITY (Low / Medium / High)
        LITIGATION RISK (Low / Medium / High)
        """

        let response = try await openAIService.sendWithCustomPrompt(
            systemPrompt: Self.caseConfidenceSystemPrompt,
            userMessage: userMessage
        )
        return CaseConfidenceParser.parse(response)
    }

    // MARK: - Document generation (returns assistant body text)

    func generateDocument(caseAnalysis: CaseAnalysis, documentType: String) async throws -> String {
        let timelineText = caseAnalysis.timeline.map { $0.description }.joined(separator: "\n")
        let prompt = """
        Generate a professional legal \(documentType).

        Use the following case analysis:

        \(caseAnalysis.summary)

        Claims:
        \(caseAnalysis.claims.joined(separator: ", "))

        Timeline:
        \(timelineText)

        Evidence:
        \(caseAnalysis.evidenceNeeded.joined(separator: ", "))

        Include formal legal language and proper formatting.
        """
        let chatMessage = ChatMessage(sender: .user, text: prompt)
        let (response, _, _) = try await openAIService.sendChat(messages: [chatMessage])
        return response
    }

    // MARK: - Prompts

    private static let fullCaseAnalysisSystemPrompt = """
    You are a legal case intake and analysis assistant. The user will provide a COMPLETE case file that may include:
    - Prior case analysis (if any)
    - Case memory (people, events, evidence, claims, damages—a structured summary of what has been established so far)
    - Timeline of events
    - Evidence document summaries
    - Voice/recording transcripts

    Analyze the ENTIRE case file and produce an updated, unified legal analysis. Use all of the information provided, including the case memory. Reason across the full case context.

    Structure your response using exactly these section headers (all caps, on their own line). Under each header, provide the relevant content. Use bullet points or numbered lists where helpful.

    CASE SUMMARY
    [Brief overview of the situation based on the full case file.]

    POTENTIAL CLAIMS
    [One or more possible legal claims, e.g. wrongful eviction, breach of contract, negligence, discrimination.]

    ESTIMATED DAMAGES
    [Range when applicable, e.g. $300k – $500k, or "N/A" / "To be assessed" if not applicable.]

    EVIDENCE NEEDED
    [List documents, witnesses, photos, records, or other evidence the user should gather.]

    TIMELINE OF EVENTS
    [Key dates and sequence of events. Use bullet points or numbered lines; include dates when known (e.g. "Jan 15 – Incident occurred").]

    NEXT STEPS
    [Concrete legal steps, e.g. 1. Preserve evidence 2. Send demand letter 3. File complaint 4. Consult an attorney.]

    DOCUMENTS TO PREPARE
    [Forms, complaints, motions, or other documents that may be required.]

    WHERE TO FILE
    [Relevant courts, agencies (e.g. EEOC, state AG, small claims), or venues to file with.]

    Keep responses clear, structured, and actionable. Do not provide legal advice; recommend consulting a licensed attorney for advice specific to their case.
    """

    private static let evidenceAnalysisSystemPrompt = """
    You are a legal evidence analyst. The user will provide the text of an evidence document (e.g. contract, notice, email, report).
    Analyze it and respond with a single JSON object only, no other text. Use this exact structure:

    {
      "summary": "Brief 1-2 sentence summary of the document and its legal relevance.",
      "violations": ["List of potential legal violations or issues suggested by the document (e.g. breach of contract, failure to provide notice)."],
      "damages": "Optional description of possible damages or monetary impact suggested by the document, or null.",
      "timelineEvents": [
        { "date": "YYYY-MM-DD or null if unknown", "description": "What happened or what the document records" }
      ],
      "deadlines": [
        { "title": "Short title (e.g. Response due)", "dueDate": "YYYY-MM-DD or null", "notes": "Optional context" }
      ],
      "missingEvidence": ["Evidence or documents that would strengthen the case but are not in this document (e.g. witness statement, repair receipt)."]
    }

    Rules:
    - Use ISO date format YYYY-MM-DD for date and dueDate when known; use null when unknown.
    - violations, timelineEvents, deadlines, and missingEvidence must be arrays (use [] if none).
    - Respond with only the JSON object, no markdown code fence or explanation.
    """

    private static let nextActionSystemPrompt = """
    You are a legal case advisor. Review the case materials and recommend the single most important next action the user should take. Be concise and actionable. Do not provide legal advice; recommend consulting a licensed attorney when appropriate. Respond with exactly two section headers on their own line: TITLE (one short line), then DESCRIPTION (one or two sentences).
    """

    private static let litigationStrategySystemPrompt = """
    You are a litigation strategy advisor. Analyze the case materials and produce a structured litigation strategy.

    Structure your response using exactly these section headers (all caps, on their own line). Under each header, provide the relevant content. Use bullet points or numbered lists for list sections.

    LEGAL THEORIES
    [Applicable legal theories or causes of action that support the case.]

    STRENGTHS
    [Key strengths of the case and supporting evidence.]

    WEAKNESSES
    [Potential weaknesses, vulnerabilities, or gaps.]

    EVIDENCE GAPS
    [Evidence that is missing or needed to strengthen the case.]

    OPPOSING ARGUMENTS
    [Arguments the opposing side is likely to make.]

    SETTLEMENT RANGE
    [Realistic settlement range or "N/A" if not applicable. One short paragraph or line.]

    LITIGATION PLAN
    [Ordered steps or phases for pursuing the case (discovery, motions, trial prep, etc.).]

    Be concise and actionable. Do not provide legal advice; recommend consulting a licensed attorney.
    """

    private static let caseConfidenceSystemPrompt = """
    You are a case strength evaluator. Assess the legal case based on the materials provided and give structured ratings.

    Structure your response using exactly these section headers (all caps, on their own line). Put a single value or short phrase on the next line after each header.

    CLAIM STRENGTH (percentage)
    [One number 0-100 representing overall claim strength. Just the number, optionally with "%".]

    EVIDENCE STRENGTH (Weak / Moderate / Strong)
    [One of: Weak, Moderate, or Strong.]

    SETTLEMENT PROBABILITY (Low / Medium / High)
    [One of: Low, Medium, or High.]

    LITIGATION RISK (Low / Medium / High)
    [One of: Low, Medium, or High.]

    Be concise. Do not provide legal advice; recommend consulting a licensed attorney.
    """

    // MARK: - Next action parsing

    private static func parseNextAction(from response: String) -> NextAction {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleRange = trimmed.range(of: "TITLE", options: .caseInsensitive)
        let descRange = trimmed.range(of: "DESCRIPTION", options: .caseInsensitive)

        if let tr = titleRange, let dr = descRange, tr.upperBound < dr.lowerBound {
            let titleSection = String(trimmed[tr.upperBound..<dr.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Next Recommended Action"
            let descSection = String(trimmed[dr.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return NextAction(
                title: titleSection.isEmpty ? "Next Recommended Action" : titleSection,
                description: descSection.isEmpty ? trimmed : descSection
            )
        }
        if let tr = titleRange {
            let after = String(trimmed[tr.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = after.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Next Recommended Action"
            return NextAction(title: firstLine, description: after)
        }
        return NextAction(
            title: "Next Recommended Action",
            description: trimmed
        )
    }
}

enum AIEngineError: LocalizedError {
    case emptyContext

    var errorDescription: String? {
        switch self {
        case .emptyContext:
            return "Case context is empty."
        }
    }
}
