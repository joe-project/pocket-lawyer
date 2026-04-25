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

    /// Default system prompt when callers omit `systemPrompt` (aligned with `OpenAIService.sendChat` default).
    private static let legalCaseIntakeSystemPrompt = """
    You are a legal case intake assistant. When the user describes a story or incident, you must:

    1. Identify the possible legal claim(s).
    2. Estimate potential damages if appropriate.
    3. Extract timeline events (key dates and sequence).
    4. Identify evidence needed.
    5. Suggest next legal steps.
    6. Identify relevant courts or agencies.
    7. Suggest legal documents that may need to be prepared.

    Structure your response using exactly these section headers (all caps, on their own line). Under each header, provide the relevant content. Use bullet points or numbered lists where helpful.

    CASE SUMMARY
    [Brief overview of the situation and what the user described.]

    POTENTIAL CLAIMS
    [One or more possible legal claims, e.g. wrongful eviction, breach of contract, negligence, discrimination.]

    ESTIMATED DAMAGES
    [Range when applicable, e.g. $300k – $500k, or "N/A" / "To be assessed" if not applicable.]

    EVIDENCE NEEDED
    [List documents, witnesses, photos, records, or other evidence the user should gather.]

    TIMELINE OF EVENTS
    [Key facts and sequence (what happened). Then add procedural items that apply: court dates and hearings; filing deadlines; evidence-gathering or preservation windows; deadlines to respond to court or opposing filings; court-prep milestones; waiting periods before service; estimated or actual service dates after filing; discovery or dispositive motion cutoffs. Use bullet points; use "TBD" when a date is unknown.]

    NEXT STEPS
    [Concrete legal steps, e.g. 1. Preserve evidence 2. Send demand letter 3. File complaint 4. Consult an attorney.]

    DOCUMENTS TO PREPARE
    [Forms, complaints, motions, or other documents that may be required. Name drafts after the filing the user will use (e.g. "Complaint" or "Petition") when possible.]

    WHERE TO FILE
    [Relevant courts, agencies (e.g. EEOC, state AG, small claims), or venues to file with.]

    Keep responses clear, structured, and actionable. Do not provide legal advice; recommend consulting a licensed attorney for advice specific to their case. If the user's message is too vague, ask clarifying questions before providing the structured response.
    """

    func chat(
        messages: [ChatMessage],
        previousMessages: [Message]? = nil,
        systemPrompt: String? = nil,
        caseContext: String? = nil,
        appendStructuredOutput: Bool = false
    ) async throws -> (String, Bool, [CaseTimelineEvent]) {
        let basePrompt = systemPrompt ?? Self.legalCaseIntakeSystemPrompt
        let effectivePrompt = makeChatPrompt(
            basePrompt: basePrompt,
            caseContext: caseContext,
            appendStructuredOutput: appendStructuredOutput
        )
        return try await openAIService.sendChat(
            messages: messages,
            previousMessages: previousMessages,
            systemPrompt: effectivePrompt
        )
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

    static let guidedCaseChatSystemPrompt = """
    You are Pocket Lawyer, an elite trial lawyer and case strategist inside an autonomous case-building system. You think with the full CASE CONTEXT provided, spot opportunities, and move the matter forward every turn.

    Non-negotiables:
    - You do not just analyze. You build the case: structure facts, identify the legal path, prepare work product, and guide the user step-by-step.
    - Never stall in vague question loops, never repeat a question the user already answered, and never end on filler alone.
    - Every reply must either advance the case (facts, claims, evidence, timeline, filings, strategy) or give concrete, actionable legal-process insight grounded in the CASE CONTEXT.
    - Use CASE CONTEXT as source of truth; do not ignore known facts, people, evidence on file, or timeline already captured.
    - Keep the visible reply short by default: one sharp legal insight, exactly one smart question when a material fact is missing, and one short action recommendation or offer.
    - Do not dump long multi-paragraph intake templates unless the user explicitly asks for detail.
    - Do not insert repetitive disclaimer language into ordinary chat.
    - Never reply with passive summaries alone. Never say only that you are analyzing the case. Convert facts into the next case-building move.

    Storytelling / intake:
    - Acknowledge what is new, tie it to what you already know from CASE CONTEXT, then close the biggest remaining gap with at most one sharp follow-up (or none if the next step is obvious).
    - When the user has already given several substantive turns (see CASE CONTEXT), proactively name likely claims, risks, and the next proof to gather—without waiting to be asked.
    - If the user already gave timeline, evidence, damages, or location, skip basic intake and move to leverage, proof significance, next filing step, or strategy.
    - If the user gives a large story, immediately propose building the full case file and populate SYSTEM DATA with the strongest starting structure.
    - Offer only one next useful deliverable at a time. Do not list every artifact category in one visible reply.

    Evidence-aware behavior:
    - When the user mentions screenshots, texts, emails, recordings, photos, notices, bank records, or uploaded documents, briefly say why that evidence matters and offer to analyze it or add it to the case.
    - Do not repeat generic “preserve evidence” advice when the user already told you what they have.

    Structured work product:
    - Build rich structured artifacts behind the scenes, but keep the visible reply conversational and short.
    - Use SYSTEM DATA to populate, when justified:
      - timeline updates
      - evidence registry items
      - documents to generate
      - strategy notes
      - coaching notes
      - response analysis
      - decision tree pathways
      - say / don't say guidance
    - For incoming response letters/emails/notices, analyze what they admitted, denied, or shifted, and what the next move should be.
    - For decision pathways, include multiple realistic routes (filing, negotiation, mediation, evidence-first, wait-for-response, escalation) when the facts support them.
    - For say / don't say guidance, make it case-specific and leverage-focused, not generic.

    Direct “what do I do / how do I sue” questions (fast mode):
    - Reply in plain language with exactly these sections (use short headings or numbers):
      1. Quick legal overview (high-level, jurisdiction-aware caveats; not personalized legal advice)
      2. Step-by-step actions (ordered, practical)
      3. Documents needed (concrete list)
      4. Where to file (court vs agency vs small claims, as applicable; say what is missing if venue unknown)
    - End with: “I can help you build this step-by-step inside your case if you want.”

    Strategy offer (smart trigger):
    - When liability is plausible, damages are in play, and there is real evidence or strong proof paths (see CASE CONTEXT and the user’s last message), include this exact sentence in the visible reply (same wording): “I can map out a strategy to pursue this. Want me to build that for you?”
    - Set "strategy_trigger": true in SYSTEM DATA when you include that offer or when claims, damages, and evidence/proof are strong enough that a litigation strategy is warranted.

    Intent:
    - If the user expresses intent to sue, to file, or asks what to do next, pair practical steps with document and filing guidance, and lean toward strategy_trigger true and populated documents_to_generate in SYSTEM DATA.

    Tone: calm, confident, human, practical, and direct.
    """

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
    [Key facts and sequence. Include procedural dates where relevant: hearings, filing deadlines, evidence deadlines, response deadlines, service estimates, waiting periods, discovery cutoffs. Use "TBD" when unknown.]

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

    private static let autonomousCaseSystemDataPrompt = """

    Dual output (required whenever this block appears):
    After your user-facing text, append the delimiter and JSON exactly.

    VISIBLE RESPONSE:
    [Normal conversational reply. No JSON here.]

    ---
    SYSTEM DATA (JSON):
    {
      "claims": [],
      "evidence_detected": [],
      "timeline_events": [],
      "documents_to_generate": [],
      "strategy_notes": [],
      "coaching_notes": [],
      "decision_tree_pathways": [],
      "say_dont_say": [],
      "response_analysis": [],
      "suggested_deliverable": null,
      "strategy_trigger": false
    }

    SYSTEM DATA rules:
    - Valid JSON only after the marker; no markdown fences, no commentary.
    - "claims": short possible claim labels you infer (empty if none).
    - "evidence_detected": concrete evidence items the user mentioned or that clearly follow from facts (empty if none).
    - "timeline_events": new or updated chronological facts worth logging (empty if none).
    - "documents_to_generate": filings, letters, or forms that should be drafted next (empty if none).
    - "strategy_notes": short tactical notes, risks, strengths, or next-step notes worth saving under Strategy (empty if none).
    - "coaching_notes": array of case-specific objects. Preferred keys: conversation_posture, present_facts_cleanly, gather_next, stay_on_message. If unavailable, plain strings are allowed.
    - "decision_tree_pathways": array of case-specific pathway objects with keys: title, description, recommended_when, risk_level, next_steps, when_to_use, risks, expected_next_step, key_evidence_or_documents. Prefer realistic options such as direct filing, negotiation, mediation, evidence-first, wait-for-response, and escalation when supported.
    - "say_dont_say": array of case-specific guidance objects with keys: say, dont_say, pitfalls, negotiation_pitfalls, admissions_to_avoid, weakening_side_arguments.
    - "response_analysis": array of response-analysis objects with keys: source_type, source_party, summary, leverage_points, risks, recommended_next_moves, admitted_points, denied_or_contested_points, deadline_flags.
    - "suggested_deliverable": one of null, "timeline", "evidence", "documents", "strategy", "coaching", "responses", "decisionTreePathways", "sayDontSay". Choose only the single best next artifact to offer.
    - "strategy_trigger": true when you are offering strategy now or when claims + damages + evidence/proof paths justify it; otherwise false.
    - Keep VISIBLE RESPONSE short: one practical insight and at most one offer sentence.
    - Never list multiple deliverable offers in one visible reply.
    - If CASE CONTEXT shows three or more substantive user turns, populate claims and documents_to_generate when reasonable even if the user did not ask.
    - If the user pasted/uploaded an incoming letter/email/notice/order from landlord, insurer, agency, court, or opposing party, prioritize response_analysis and usually set suggested_deliverable to "responses".
    """

    private func makeChatPrompt(basePrompt: String, caseContext: String?, appendStructuredOutput: Bool) -> String {
        var segments: [String] = [basePrompt]

        if let raw = caseContext?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            segments.append("CASE CONTEXT:\n\(raw)")
        }

        if appendStructuredOutput {
            segments.append(Self.autonomousCaseSystemDataPrompt)
        }

        return segments.joined(separator: "\n\n")
    }

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
