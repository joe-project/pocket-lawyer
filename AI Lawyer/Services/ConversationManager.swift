import Foundation
import Combine

@MainActor
final class ConversationManager: ObservableObject {
    struct AppliedCaseUpdate {
        let caseId: UUID
        let subfolder: CaseSubfolder
        let fileId: UUID?
        let confirmation: String
    }

    private enum GuidedCaseStage: String {
        case initialSummary
        case awaitingClarificationAnswers
        case awaitingMoreClarificationAnswers
        case awaitingFinalClarificationAnswers
        case awaitingStrategyConsent
        case awaitingProceedConsent
        case awaitingQuestionDecision
        case awaitingDocumentConsent
        case openQuestionAnswer
        case completed
    }

    private enum PendingCaseUpdate {
        case addToEvidence(caseId: UUID, sourceText: String, attachmentNames: [String], attachmentContents: [String])
        case updateTimeline(caseId: UUID, sourceText: String)
    }

    @Published var messages: [Message] = []
    /// True after answering a user question while intake was active; UI can show "Resume intake".
    @Published var offeringResumeIntake: Bool = false
    @Published private(set) var pendingFolderSuggestionCaseId: UUID?
    @Published private(set) var pendingCaseUpdateCaseId: UUID?
    /// Case ids currently being analyzed by background reasoning (and/or awaiting AI pipeline completion).
    @Published private(set) var analyzingCaseIds: Set<UUID> = []

    private let aiEngine: AIEngine
    private let caseReasoningEngine: CaseReasoningEngine
    private let caseBriefEngine = CaseBriefEngine()
    private let legalSignalExtractor = LegalSignalExtractor()
    private let conversationPlanner = ConversationPlanner()
    private let messageBatcher = MessageBatcher()
    private let jobQueue = AIJobQueue()
    private let contextCache = CaseContextCache()
    private let analysisResultCache = CaseAnalysisResultCache()
    private var isProcessingReasoning = false
    private var lastFolderSuggestionUserCount: [UUID: Int] = [:]
    private var guidedStages: [UUID: GuidedCaseStage] = [:]
    private var pendingCaseUpdates: [UUID: PendingCaseUpdate] = [:]
    private var lastSuggestedUpdateMessageIds: [UUID: UUID] = [:]
    private var lastStrategyOfferUserCount: [UUID: Int] = [:]

    /// Last assistant-visible text per case (for “save that” / “add this to strategy” without re-sending).
    private var lastAssistantContentByCase: [UUID: String] = [:]

    private struct NLPendingDisambiguation {
        let listenerCaseId: UUID
        let options: [(id: UUID, title: String)]
        let sourceText: String
        let attachmentNames: [String]
        let attachmentContents: [String]
        let subfolder: CaseSubfolder
        let intentKind: ChatCaseIntentKind
    }

    private var pendingNLDisambiguation: NLPendingDisambiguation?

    /// When set, case analysis is stored here and the dashboard can refresh from it.
    weak var caseManager: CaseManager?
    /// When set, used to build full case context (timeline, evidence, recordings) for AI reasoning.
    weak var caseTreeViewModel: CaseTreeViewModel?
    /// Called when case analysis is updated so the UI (e.g. CaseDashboard) can refresh. Passes (caseId, analysis).
    var onCaseAnalysisUpdated: ((UUID, CaseAnalysis) -> Void)?

    /// When set, used to fetch legal references (citations from CourtListener, GovInfo, LII) to include in case context so AI responses can cite sources.
    var legalResearchForCase: ((UUID) async -> String)?

    init(caseReasoningEngine: CaseReasoningEngine? = nil, aiEngine: AIEngine? = nil) {
        let engine = aiEngine ?? .shared
        self.aiEngine = engine
        self.caseReasoningEngine = caseReasoningEngine ?? CaseReasoningEngine(aiEngine: engine)
        NotificationCenter.default.addObserver(
            forName: CaseChangeNotifications.timelineChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let caseId = note.object as? UUID else { return }
            Task { @MainActor in
                self.enqueueReasoning(caseId: caseId)
            }
        }
    }

    func messagesForCase(caseId: UUID) -> [Message] {
        messages.filter { $0.caseId == caseId }
    }

    func messagesForCaseFile(caseId: UUID?, fileId: UUID?) -> [Message] {
        guard let id = caseId else {
            // When there is no active case, keep file-bound messages empty so the UI can show its placeholder.
            return messages.filter { $0.caseId == nil && $0.fileId == nil }
        }

        if let fid = fileId {
            return messages.filter { $0.caseId == id && $0.fileId == fid }
        } else {
            // When no file is selected, keep the "current" conversation tied to file-less messages
            // (typically the triggering user message before the first save creates a file version).
            return messages.filter { $0.caseId == id && $0.fileId == nil }
        }
    }

    /// Returns messages for the given case, or messages with no case when caseId is nil.
    func messagesForCase(caseId: UUID?) -> [Message] {
        guard let id = caseId else { return messages.filter { $0.caseId == nil } }
        return messages.filter { $0.caseId == id }
    }

    func addMessage(_ message: Message) {
        messages.append(message)
        switch message.role {
        case "user":
            print("🔥 USER MESSAGE ADDED")
        case "assistant":
            print("🔥 AI RESPONSE ADDED:", message.content)
        default:
            print("🔥 MESSAGE ADDED [\(message.role)]")
        }
        print("MESSAGE CASE ID:", message.caseId?.uuidString ?? "nil")
        if message.role == "assistant", let cid = message.caseId {
            lastAssistantContentByCase[cid] = message.content
        }
        messageBatcher.addMessage(message)
        if messageBatcher.shouldProcessBatch() {
            let batch = messageBatcher.flushBatch()
            let caseIds = Set(batch.compactMap(\.caseId))
            for caseId in caseIds {
                jobQueue.addJob(AIJob(id: UUID(), type: "case_reasoning", caseId: caseId))
                analyzingCaseIds.insert(caseId)
            }
            ensureReasoningProcessorRunning()
        }
    }

    func addLocalAssistantMessage(_ content: String, caseId: UUID?) {
        let localMessage = Message(
            id: UUID(),
            caseId: caseId,
            fileId: nil,
            role: "assistant",
            content: content,
            timestamp: Date()
        )
        messages.append(localMessage)
        if let cid = caseId {
            lastAssistantContentByCase[cid] = content
        }
    }

    func clearPendingFolderSuggestion() {
        pendingFolderSuggestionCaseId = nil
    }

    func clearPendingCaseUpdateSuggestion(for caseId: UUID) {
        pendingCaseUpdates.removeValue(forKey: caseId)
        if pendingCaseUpdateCaseId == caseId {
            pendingCaseUpdateCaseId = nil
        }
    }

    func hasPendingCaseUpdate(for caseId: UUID) -> Bool {
        pendingCaseUpdates[caseId] != nil
    }

    func resolvePendingCaseUpdateReply(_ text: String, currentCaseId: UUID) -> AppliedCaseUpdate? {
        guard let pending = pendingCaseUpdates[currentCaseId] else { return nil }
        guard let decision = normalizedDecision(text) else { return nil }

        defer { clearPendingCaseUpdateSuggestion(for: currentCaseId) }

        guard decision else {
            let confirmation = "Okay. I’ll leave your folders as they are for now."
            addLocalAssistantMessage(confirmation, caseId: currentCaseId)
            return AppliedCaseUpdate(caseId: currentCaseId, subfolder: .history, fileId: nil, confirmation: confirmation)
        }

        switch pending {
        case .addToEvidence(let caseId, let sourceText, let attachmentNames, let attachmentContents):
            let applied = applyEvidenceUpdate(
                caseId: caseId,
                sourceText: sourceText,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )
            let title = caseTreeViewModel?.cases.first(where: { $0.id == caseId })?.title ?? "this case"
            let confirmation = "Added that to the evidence folder for \(title)."
            addLocalAssistantMessage(confirmation, caseId: caseId)
            return AppliedCaseUpdate(caseId: caseId, subfolder: .evidence, fileId: applied, confirmation: confirmation)
        case .updateTimeline(let caseId, let sourceText):
            let applied = applyTimelineUpdate(caseId: caseId, sourceText: sourceText)
            let title = caseTreeViewModel?.cases.first(where: { $0.id == caseId })?.title ?? "this case"
            let confirmation = "Updated the timeline for \(title)."
            addLocalAssistantMessage(confirmation, caseId: caseId)
            return AppliedCaseUpdate(caseId: caseId, subfolder: .timeline, fileId: applied, confirmation: confirmation)
        }
    }

    /// Chat-driven case actions: create case, route adds to evidence/timeline/strategy/etc., fuzzy match by name.
    func handleNaturalLanguageCaseIntent(
        text: String,
        currentCaseId: UUID,
        attachmentNames: [String],
        attachmentContents: [String]
    ) -> AppliedCaseUpdate? {
        guard let tree = caseTreeViewModel else { return nil }

        if let pending = pendingNLDisambiguation, pending.listenerCaseId == currentCaseId {
            if let idx = ChatCaseIntentRouter.resolveDisambiguationIndex(from: text, optionCount: pending.options.count) {
                pendingNLDisambiguation = nil
                let target = pending.options[idx].id
                return executeNLAdd(
                    caseId: target,
                    subfolder: pending.subfolder,
                    intentKind: pending.intentKind,
                    sourceText: pending.sourceText,
                    attachmentNames: pending.attachmentNames,
                    attachmentContents: pending.attachmentContents
                )
            }
            if normalizedDecision(text) == false {
                pendingNLDisambiguation = nil
                let msg = "Okay—tell me which case name to use, or say “create case …” to start a new one."
                addLocalAssistantMessage(msg, caseId: currentCaseId)
                return AppliedCaseUpdate(caseId: currentCaseId, subfolder: .history, fileId: nil, confirmation: msg)
            }
        }

        guard let parsed = ChatCaseIntentRouter.parse(
            rawText: text,
            hasAttachments: !attachmentNames.isEmpty
        ) else { return nil }

        switch parsed.kind {
        case .createCase:
            return handleNLCreateCase(
                text: text,
                currentCaseId: currentCaseId,
                parsed: parsed,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )
        case .saveLastAssistantReply:
            let body = lastAssistantContentByCase[currentCaseId] ?? ""
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let msg = "I don’t have a recent assistant reply to save yet. After I respond, you can say “save that to strategy” (or timeline/notes)."
                addLocalAssistantMessage(msg, caseId: currentCaseId)
                return AppliedCaseUpdate(caseId: currentCaseId, subfolder: .history, fileId: nil, confirmation: msg)
            }
            return executeNLAdd(
                caseId: currentCaseId,
                subfolder: parsed.targetSubfolder,
                intentKind: parsed.kind,
                sourceText: body,
                attachmentNames: [],
                attachmentContents: []
            )
        case .createTask:
            fallthrough
        case .addToCase, .addToEvidence, .addToTimeline, .addToStrategy, .addToNotes, .addToResearch, .addToDocuments:
            return handleNLAddToResolvedCase(
                text: text,
                currentCaseId: currentCaseId,
                parsed: parsed,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )
        case .askForConfirmation, .normalChatResponse:
            return nil
        }
    }

    private func handleNLCreateCase(
        text: String,
        currentCaseId: UUID,
        parsed: ChatCaseIntentParseResult,
        attachmentNames: [String],
        attachmentContents: [String]
    ) -> AppliedCaseUpdate? {
        guard let tree = caseTreeViewModel else { return nil }
        let rawTitle = parsed.titleOrQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? suggestedFolderTitle(for: currentCaseId) : rawTitle

        if let dup = tree.cases.first(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(title) == .orderedSame }) {
            let msg = "You already have a case named “\(dup.title)”. Open it in the sidebar, or pick a different name."
            addLocalAssistantMessage(msg, caseId: currentCaseId)
            return AppliedCaseUpdate(caseId: currentCaseId, subfolder: .history, fileId: nil, confirmation: msg)
        }

        let newId = tree.createNewCase(title: title, category: .inProgress)
        tree.revealStandardSubfolders(caseId: newId)

        let userMsg = Message(
            id: UUID(),
            caseId: newId,
            fileId: nil,
            role: "user",
            content: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !attachmentNames.isEmpty ? "(attachment)" : text,
            timestamp: Date(),
            attachmentNames: attachmentNames,
            attachmentContents: attachmentContents
        )
        addMessage(userMsg)

        if !attachmentNames.isEmpty {
            _ = applyEvidenceUpdate(
                caseId: newId,
                sourceText: text,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )
        }

        let msg = "Done. I created “\(title)” and set up its sections\(attachmentNames.isEmpty ? "" : ", and added your attachment(s) to Evidence"). You’re now in that case."
        addLocalAssistantMessage(msg, caseId: newId)
        return AppliedCaseUpdate(caseId: newId, subfolder: .evidence, fileId: nil, confirmation: msg)
    }

    private func handleNLAddToResolvedCase(
        text: String,
        currentCaseId: UUID,
        parsed: ChatCaseIntentParseResult,
        attachmentNames: [String],
        attachmentContents: [String]
    ) -> AppliedCaseUpdate? {
        guard let tree = caseTreeViewModel else { return nil }
        let query = parsed.titleOrQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetId: UUID?

        if query.isEmpty {
            targetId = currentCaseId
        } else {
            let ranked = ChatCaseIntentRouter.rankedCaseMatches(query: query, cases: tree.cases)
            if ranked.isEmpty {
                let msg = "I couldn’t find a case matching “\(query)”. Say create case \(query) to start one, or use the exact sidebar title."
                addLocalAssistantMessage(msg, caseId: currentCaseId)
                return AppliedCaseUpdate(caseId: currentCaseId, subfolder: .history, fileId: nil, confirmation: msg)
            }
            let best = ranked[0]
            let second = ranked.count > 1 ? ranked[1] : nil
            if let s = second, best.score < 0.9, (best.score - s.score) < 0.18 {
                let top = Array(ranked.prefix(3))
                pendingNLDisambiguation = NLPendingDisambiguation(
                    listenerCaseId: currentCaseId,
                    options: top.map { ($0.folder.id, $0.folder.title) },
                    sourceText: nlSourceText(text: text, currentCaseId: currentCaseId, parsed: parsed, attachmentNames: attachmentNames),
                    attachmentNames: attachmentNames,
                    attachmentContents: attachmentContents,
                    subfolder: parsed.targetSubfolder,
                    intentKind: parsed.kind
                )
                let list = top.enumerated().map { "\($0.offset + 1). \($0.element.folder.title)" }.joined(separator: "\n")
                let msg = "Which case did you mean?\n\(list)\n\nReply with a number (1, 2, …), or say no to cancel."
                addLocalAssistantMessage(msg, caseId: currentCaseId)
                return AppliedCaseUpdate(caseId: currentCaseId, subfolder: .history, fileId: nil, confirmation: msg)
            }
            targetId = best.folder.id
        }

        guard let caseId = targetId else { return nil }
        let source = nlSourceText(text: text, currentCaseId: currentCaseId, parsed: parsed, attachmentNames: attachmentNames)
        return executeNLAdd(
            caseId: caseId,
            subfolder: parsed.targetSubfolder,
            intentKind: parsed.kind,
            sourceText: source,
            attachmentNames: attachmentNames,
            attachmentContents: attachmentContents
        )
    }

    private func nlSourceText(
        text: String,
        currentCaseId: UUID,
        parsed: ChatCaseIntentParseResult,
        attachmentNames: [String]
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !parsed.refersToAttachmentOrDemonstrative || attachmentNames.isEmpty {
            return trimmed
        }
        if parsed.refersToAttachmentOrDemonstrative && attachmentNames.isEmpty {
            return reusableSourceText(for: currentCaseId, fallback: text)
        }
        return trimmed.isEmpty ? reusableSourceText(for: currentCaseId, fallback: text) : trimmed
    }

    private func executeNLAdd(
        caseId: UUID,
        subfolder: CaseSubfolder,
        intentKind: ChatCaseIntentKind,
        sourceText: String,
        attachmentNames: [String],
        attachmentContents: [String]
    ) -> AppliedCaseUpdate? {
        guard let tree = caseTreeViewModel else { return nil }
        let title = tree.cases.first(where: { $0.id == caseId })?.title ?? "this case"
        var fileId: UUID?
        var confirmation: String

        switch intentKind {
        case .createTask:
            let stripped = textAfterTaskVerb(sourceText)
            let taskTitle = String(stripped.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
            let head = taskTitle.isEmpty ? "Task from chat" : taskTitle
            tree.addTimelineEvent(
                TimelineEvent(
                    kind: .task,
                    title: head,
                    summary: sourceText.prefix(500).description,
                    createdAt: Date(),
                    documentId: nil,
                    subfolder: .timeline
                ),
                caseId: caseId
            )
            confirmation = "Added a task to \(title)."

        case .addToTimeline:
            fileId = applyTimelineUpdate(caseId: caseId, sourceText: sourceText)
            confirmation = "Added to the timeline for \(title)."

        case .addToEvidence:
            fileId = applyEvidenceUpdate(
                caseId: caseId,
                sourceText: sourceText,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )
            confirmation = "Added to \(title) evidence."

        case .addToStrategy:
            let body = compositeBody(sourceText: sourceText, attachmentNames: attachmentNames, attachmentContents: attachmentContents)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                confirmation = "Nothing to save—try adding a short note after your command."
                addLocalAssistantMessage(confirmation, caseId: caseId)
                return AppliedCaseUpdate(caseId: caseId, subfolder: .response, fileId: nil, confirmation: confirmation)
            }
            fileId = tree.addVersionedTextArtifact(
                caseId: caseId,
                subfolder: .response,
                baseName: "Strategy Notes",
                content: body,
                responseTag: .strategy,
                timelineTitle: "Strategy note saved",
                timelineSummary: body.prefix(180).description
            )
            confirmation = "Saved a strategy note in \(title)."

        case .addToResearch:
            let body = compositeBody(sourceText: sourceText, attachmentNames: attachmentNames, attachmentContents: attachmentContents)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                confirmation = "Nothing to save."
                addLocalAssistantMessage(confirmation, caseId: caseId)
                return AppliedCaseUpdate(caseId: caseId, subfolder: .history, fileId: nil, confirmation: confirmation)
            }
            fileId = tree.addVersionedTextArtifact(
                caseId: caseId,
                subfolder: .history,
                baseName: "Research Findings",
                content: body,
                responseTag: .note,
                timelineTitle: "Research saved",
                timelineSummary: body.prefix(180).description
            )
            confirmation = "Saved research notes in \(title)."

        case .addToDocuments:
            let body = compositeBody(sourceText: sourceText, attachmentNames: attachmentNames, attachmentContents: attachmentContents)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                confirmation = "Nothing to save."
                addLocalAssistantMessage(confirmation, caseId: caseId)
                return AppliedCaseUpdate(caseId: caseId, subfolder: .documents, fileId: nil, confirmation: confirmation)
            }
            fileId = tree.addVersionedTextArtifact(
                caseId: caseId,
                subfolder: .documents,
                baseName: "From chat",
                content: body,
                responseTag: .draft,
                timelineTitle: "Document note saved",
                timelineSummary: body.prefix(180).description
            )
            confirmation = "Saved to Documents in \(title)."

        case .addToNotes, .addToCase, .saveLastAssistantReply:
            let body = compositeBody(sourceText: sourceText, attachmentNames: attachmentNames, attachmentContents: attachmentContents)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                confirmation = "Nothing to save."
                addLocalAssistantMessage(confirmation, caseId: caseId)
                return AppliedCaseUpdate(caseId: caseId, subfolder: .history, fileId: nil, confirmation: confirmation)
            }
            fileId = applyHistoryUpdate(caseId: caseId, sourceText: body)
            confirmation = "Saved to notes/history for \(title)."

        case .createCase, .askForConfirmation, .normalChatResponse:
            return nil
        }

        addLocalAssistantMessage(confirmation, caseId: caseId)
        return AppliedCaseUpdate(caseId: caseId, subfolder: subfolder, fileId: fileId, confirmation: confirmation)
    }

    private func compositeBody(sourceText: String, attachmentNames: [String], attachmentContents: [String]) -> String {
        var parts: [String] = []
        let t = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != "(attachment)" { parts.append(t) }
        for (i, name) in attachmentNames.enumerated() {
            let c = i < attachmentContents.count ? attachmentContents[i] : ""
            if c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("[Attachment: \(name)]")
            } else {
                parts.append("[Attachment: \(name)]\n\(c)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func textAfterTaskVerb(_ raw: String) -> String {
        let p = #"^(?i)(add|save|put|create)\s+(a\s+)?(task|todo|to-?do|reminder)\s*:?\s*"#
        guard let range = raw.range(of: p, options: .regularExpression) else { return raw }
        return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func handleDirectCaseCommandIfNeeded(
        _ text: String,
        currentCaseId: UUID,
        attachmentNames: [String],
        attachmentContents: [String]
    ) -> AppliedCaseUpdate? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard looksLikeCrossCaseCommand(normalized) else { return nil }

        let targetCaseId = targetCaseId(from: normalized) ?? currentCaseId

        if normalized.contains("timeline")
            || normalized.contains("deadline")
            || normalized.contains("court date")
            || normalized.contains("serve")
            || normalized.contains("hearing")
            || normalized.contains("filing")
            || normalized.contains("waiting period")
            || normalized.contains("gathering")
            || normalized.contains("prep ") {
            let sourceText = reusableSourceText(for: currentCaseId, fallback: text)
            let fileId = applyTimelineUpdate(caseId: targetCaseId, sourceText: sourceText)
            let title = caseTreeViewModel?.cases.first(where: { $0.id == targetCaseId })?.title ?? "this case"
            let confirmation = "Updated the timeline for \(title)."
            addLocalAssistantMessage(confirmation, caseId: targetCaseId)
            return AppliedCaseUpdate(caseId: targetCaseId, subfolder: .timeline, fileId: fileId, confirmation: confirmation)
        }

        if normalized.contains("evidence") || !attachmentNames.isEmpty || normalized.contains("photo") || normalized.contains("image") || normalized.contains("text message") {
            let sourceText = reusableSourceText(for: currentCaseId, fallback: text)
            let fileId = applyEvidenceUpdate(
                caseId: targetCaseId,
                sourceText: sourceText,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )
            let title = caseTreeViewModel?.cases.first(where: { $0.id == targetCaseId })?.title ?? "this case"
            let confirmation = "Added that to the evidence folder for \(title)."
            addLocalAssistantMessage(confirmation, caseId: targetCaseId)
            return AppliedCaseUpdate(caseId: targetCaseId, subfolder: .evidence, fileId: fileId, confirmation: confirmation)
        }

        if normalized.contains("document") || normalized.contains("note") || normalized.contains("history") || normalized.contains("case") {
            let sourceText = reusableSourceText(for: currentCaseId, fallback: text)
            let fileId = applyHistoryUpdate(caseId: targetCaseId, sourceText: sourceText)
            let title = caseTreeViewModel?.cases.first(where: { $0.id == targetCaseId })?.title ?? "this case"
            let confirmation = "Added that to \(title)."
            addLocalAssistantMessage(confirmation, caseId: targetCaseId)
            return AppliedCaseUpdate(caseId: targetCaseId, subfolder: .history, fileId: fileId, confirmation: confirmation)
        }

        return nil
    }

    func suggestedFolderTitle(for caseId: UUID) -> String {
        let text = messagesForCase(caseId: caseId)
            .filter { $0.role == "user" }
            .suffix(3)
            .map(\.content)
            .joined(separator: " ")

        let cleaned = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "New Case Folder" : cleaned.capitalized
    }

    private func stage(for caseId: UUID?) -> GuidedCaseStage {
        guard let caseId else { return .initialSummary }
        return guidedStages[caseId] ?? .initialSummary
    }

    private func setStage(_ stage: GuidedCaseStage, for caseId: UUID?) {
        guard let caseId else { return }
        guidedStages[caseId] = stage
    }

    private func localGuidedReply(for stage: GuidedCaseStage, caseId: UUID, latestUserMessage: String) -> (content: String, targetSubfolder: CaseSubfolder, nextStage: GuidedCaseStage)? {
        let payload = legalSignalExtractor.extract(from: latestUserMessage)
        let userMessageCount = messagesForCase(caseId: caseId).filter { $0.role == "user" }.count
        let plan = conversationPlanner.makePlan(payload: payload, userMessageCount: userMessageCount)
        let questionText = Array(plan.nextQuestions.prefix(2)).map(\.text).joined(separator: " ")

        switch stage {
        case .initialSummary:
            return (
                """
                \(plan.summaryLead ?? "Got it. Let’s build this step by step.")

                \(questionText.isEmpty ? "Start with the moment it began. What happened first?" : questionText)
                """,
                .history,
                .awaitingClarificationAnswers
            )

        case .awaitingClarificationAnswers:
            return (
                """
                \(plan.summaryLead ?? "That helps. I’m organizing this as we go.")

                \(questionText.isEmpty ? "Before strategy, I still need the strongest documents and the timeline anchors." : questionText)
                """,
                .history,
                .awaitingMoreClarificationAnswers
            )

        case .awaitingMoreClarificationAnswers:
            return (
                """
                \(plan.summaryLead ?? "I see the shape of it now.")

                \(questionText.isEmpty ? "Is there a deadline, hearing, filing date, or response date I should anchor the timeline to?" : questionText)
                """,
                .history,
                .awaitingFinalClarificationAnswers
            )

        case .awaitingFinalClarificationAnswers:
            return (
                """
                That gives me a much clearer picture.

                Would you like me to put together a short strategy for you?
                """,
                .history,
                .awaitingStrategyConsent
            )

        case .awaitingStrategyConsent, .awaitingProceedConsent, .awaitingQuestionDecision, .awaitingDocumentConsent, .openQuestionAnswer, .completed:
            return nil
        }
    }

    private func responseDelayNanoseconds(for text: String) -> UInt64 {
        let trimmedCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let base: UInt64 = 180_000_000
        let extra = min(UInt64(trimmedCount) * 1_000_000, 220_000_000)
        return base + extra
    }

    private func pauseBeforeReply(_ text: String) async {
        try? await Task.sleep(nanoseconds: responseDelayNanoseconds(for: text))
    }

    private func substantiveUserTurnCount(for caseId: UUID) -> Int {
        messagesForCase(caseId: caseId).filter { msg in
            guard msg.role == "user" else { return false }
            return msg.content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 30
        }.count
    }

    private func combinedKnownFactsText(caseId: UUID?, latestUserMessage: String) -> String {
        var parts: [String] = [latestUserMessage]

        if let caseId {
            let recent = messagesForCase(caseId: caseId)
                .suffix(10)
                .map(\.content)
                .joined(separator: "\n")
            let memory = CaseMemoryStore.shared.memoryOrEmpty(for: caseId)
            let analysis = caseManager?.getCase(byId: caseId)?.analysis

            parts.append(recent)
            parts.append(memory.people.joined(separator: "\n"))
            parts.append(memory.events.joined(separator: "\n"))
            parts.append(memory.evidence.joined(separator: "\n"))
            parts.append(memory.claims.joined(separator: "\n"))
            if let damages = memory.damagesEstimate { parts.append(damages) }
            if let analysis {
                parts.append(analysis.summary)
                parts.append(analysis.claims.joined(separator: "\n"))
                parts.append(analysis.timeline.map(\.description).joined(separator: "\n"))
                parts.append(analysis.evidenceNeeded.joined(separator: "\n"))
                parts.append(analysis.documents.joined(separator: "\n"))
                parts.append(analysis.filingLocations.joined(separator: "\n"))
            }
        }

        return parts.joined(separator: "\n").lowercased()
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func questionIsAlreadyAnswered(_ question: FollowUpQuestion, knownText: String) -> Bool {
        let q = question.text.lowercased()

        if q.contains("city and state") || q.contains("state is this") || q.contains("property in") {
            return containsAny(knownText, ["texas", "california", "florida", "new york", "illinois", "georgia", "ohio"])
        }
        if q.contains("how long") || q.contains("when did it start") || q.contains("what happened first") || q.contains("about when") {
            return containsAny(knownText, ["day", "days", "week", "weeks", "month", "months", "year", "years", "since", "yesterday", "today"])
        }
        if q.contains("lease") || q.contains("current on rent") {
            return containsAny(knownText, ["lease", "rental agreement", "rent", "tenant"])
        }
        if q.contains("emails") || q.contains("texts") || q.contains("written notice") || q.contains("messages") || q.contains("write-ups") || q.contains("pay records") {
            return containsAny(knownText, ["email", "emails", "text", "texts", "message", "messages", "notice", "letter", "write-up", "writeups", "pay records", "pay stub"])
        }
        if q.contains("costs") || q.contains("health issues") || q.contains("working bathroom") {
            return containsAny(knownText, ["cost", "costs", "hotel", "medical", "health", "bathroom", "couldn't use", "could not use", "injury", "damage"])
        }
        if q.contains("served") || q.contains("court is it in") || q.contains("petition") || q.contains("hearing notice") || q.contains("proof of service") {
            return containsAny(knownText, ["served", "court", "petition", "hearing", "proof of service", "service"])
        }
        if q.contains("who made the decision") || q.contains("took the action against you") {
            return containsAny(knownText, ["boss", "manager", "hr", "supervisor", "employer", "company"])
        }

        return false
    }

    private func unansweredFollowUpQuestions(for caseId: UUID?, latestUserMessage: String, payload: CaseUpdatePayload) -> [FollowUpQuestion] {
        let knownText = combinedKnownFactsText(caseId: caseId, latestUserMessage: latestUserMessage)
        return payload.followUpQuestions.filter { !questionIsAlreadyAnswered($0, knownText: knownText) }
    }

    private func promptGuidanceForMissingFacts(caseId: UUID?, latestUserMessage: String, payload: CaseUpdatePayload) -> String {
        let remaining = unansweredFollowUpQuestions(for: caseId, latestUserMessage: latestUserMessage, payload: payload)
        guard let first = remaining.first else {
            return "Known facts are already sufficient for the next step. Do not ask a clarifying question unless a truly material gap remains."
        }
        return """
        Missing-facts check:
        - Do not ask about anything already answered in CASE CONTEXT or the latest user message.
        - If you ask a clarifying question, ask only this materially useful one: \(first.text)
        - If the answer is already implicit, skip the question and move straight to insight and next action.
        """
    }

    private func buildAutonomousCaseContext(for caseId: UUID) -> String {
        let memory = CaseMemoryStore.shared.memoryOrEmpty(for: caseId)
        let analysis = caseManager?.getCase(byId: caseId)?.analysis
        let cachedStrategy = contextCache.get(forCaseId: caseId)?.strategy
        let evidenceFiles = caseTreeViewModel?.files(for: caseId, subfolder: .evidence) ?? []
        let timeline = caseTreeViewModel?.events(for: caseId) ?? []
        let recentMessages = messagesForCase(caseId: caseId)
            .suffix(8)
            .map { "\($0.role.capitalized): \($0.content)" }

        let knownFacts = [
            analysis?.summary,
            memory.events.first,
            memory.damagesEstimate.map { "Damages: \($0)" }
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        let people = memory.people
        let timelineSummary = (
            analysis?.timeline.map(\.description) ??
            timeline.map { "\($0.title)\($0.summary.map { ": \($0)" } ?? "")" }
        )
        let evidenceCollected = Array(Set(memory.evidence + evidenceFiles.map(\.name)))
        let missingEvidence = analysis?.evidenceNeeded ?? []
        let currentStrategy = strategySummary(from: cachedStrategy)
        let substantiveTurns = substantiveUserTurnCount(for: caseId)

        let claimsFromAnalysis = (analysis?.claims ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let damagesAnalysis = analysis?.estimatedDamages.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let docsFromAnalysis = (analysis?.documents ?? []).prefix(8).joined(separator: ", ")
        let filingFromAnalysis = (analysis?.filingLocations ?? []).prefix(5).joined(separator: ", ")
        let nextStepsAnalysis = (analysis?.nextSteps ?? []).prefix(5).joined(separator: " | ")

        return """
        - Known facts: \(knownFacts.isEmpty ? "None confirmed yet." : knownFacts.joined(separator: " | "))
        - People involved: \(people.isEmpty ? "None identified yet." : people.joined(separator: ", "))
        - Timeline summary: \(timelineSummary.isEmpty ? "No anchored timeline yet." : timelineSummary.prefix(8).joined(separator: " | "))
        - Evidence collected: \(evidenceCollected.isEmpty ? "No evidence logged yet." : evidenceCollected.prefix(10).joined(separator: ", "))
        - Missing evidence: \(missingEvidence.isEmpty ? "Not clearly identified yet." : missingEvidence.prefix(8).joined(separator: ", "))
        - Current strategy: \(currentStrategy ?? "No formal strategy yet.")
        - Analysis claims (if any): \(claimsFromAnalysis.isEmpty ? "None yet." : claimsFromAnalysis.prefix(8).joined(separator: "; "))
        - Estimated damages (analysis): \(damagesAnalysis.isEmpty ? "Not set." : damagesAnalysis)
        - Suggested documents (analysis): \(docsFromAnalysis.isEmpty ? "None yet." : docsFromAnalysis)
        - Where to file (analysis): \(filingFromAnalysis.isEmpty ? "Not set." : filingFromAnalysis)
        - Next steps (analysis): \(nextStepsAnalysis.isEmpty ? "Not set." : nextStepsAnalysis)
        - Substantive user turns (approx.): \(substantiveTurns). If this is 3 or more, populate SYSTEM DATA claims and documents_to_generate when appropriate.
        - Recent conversation: \(recentMessages.isEmpty ? "No prior turns." : recentMessages.joined(separator: " || "))
        """
    }

    private func strategySummary(from strategy: LitigationStrategy?) -> String? {
        guard let strategy else { return nil }
        let pieces = [
            strategy.legalTheories.first.map { "Theories: \($0)" },
            strategy.strengths.first.map { "Strength: \($0)" },
            strategy.weaknesses.first.map { "Weakness: \($0)" },
            strategy.litigationPlan.first.map { "Plan: \($0)" }
        ].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: " | ")
    }

    private struct ParsedChatEnvelope {
        let visibleResponse: String
        let payload: CaseUpdatePayload?
    }

    private struct ChatSystemDataEnvelope: Decodable {
        let claims: [String]
        let evidence_detected: [String]
        let timeline_events: [String]
        let documents_to_generate: [String]
        let strategy_trigger: Bool
    }

    private func jsonStringAfterSystemDataMarker(_ response: String) -> String? {
        guard let markerRange = response.range(of: "SYSTEM DATA (JSON):", options: .caseInsensitive) else {
            return nil
        }
        var jsonText = String(response[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```") {
            jsonText.removeFirst(3)
            jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonText.lowercased().hasPrefix("json") {
                jsonText = String(jsonText.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let fence = jsonText.range(of: "```") {
                jsonText = String(jsonText[..<fence.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let firstBrace = jsonText.firstIndex(of: "{"),
           let lastBrace = jsonText.lastIndex(of: "}") {
            jsonText = String(jsonText[firstBrace...lastBrace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return jsonText.isEmpty ? nil : jsonText
    }

    private func parseChatEnvelope(_ response: String) -> ParsedChatEnvelope {
        guard let markerRange = response.range(of: "SYSTEM DATA (JSON):", options: .caseInsensitive) else {
            return ParsedChatEnvelope(
                visibleResponse: response.trimmingCharacters(in: .whitespacesAndNewlines),
                payload: nil
            )
        }

        let visible = response[..<markerRange.lowerBound]
            .replacingOccurrences(of: "VISIBLE RESPONSE:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "---", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonText = jsonStringAfterSystemDataMarker(response),
              let data = jsonText.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ChatSystemDataEnvelope.self, from: data) else {
            return ParsedChatEnvelope(
                visibleResponse: visible.isEmpty ? response.trimmingCharacters(in: .whitespacesAndNewlines) : visible,
                payload: nil
            )
        }

        let payload = CaseUpdatePayload(
            extractedFacts: envelope.claims.map { ExtractedLegalFact(kind: .claim, value: $0, confidence: 0.72) },
            timelineEvents: envelope.timeline_events.map { CaseTimelineEvent(date: nil, description: $0) },
            evidenceItems: envelope.evidence_detected.map { WorkflowEvidenceItem(title: $0, category: "Detected", status: .have, isTentative: true) },
            documentRequirements: envelope.documents_to_generate.map {
                DocumentRequirement(title: $0, urgency: .soon, stage: .filing, isTentative: true)
            },
            strategyNotes: envelope.claims.map { StrategyNote(category: .strength, text: "Potential claim identified: \($0)", isTentative: true) },
            shouldOfferTimelineUpdate: !envelope.timeline_events.isEmpty,
            shouldOfferEvidenceUpdate: !envelope.evidence_detected.isEmpty,
            shouldOfferDocumentChecklist: !envelope.documents_to_generate.isEmpty,
            shouldOfferStrategy: envelope.strategy_trigger
        )

        return ParsedChatEnvelope(
            visibleResponse: visible.isEmpty ? response.trimmingCharacters(in: .whitespacesAndNewlines) : visible,
            payload: payload
        )
    }

    private func caseHasLiabilityDamagesEvidence(caseId: UUID, payload: CaseUpdatePayload) -> Bool {
        guard let analysis = caseManager?.getCase(byId: caseId)?.analysis else { return false }
        let claims = analysis.claims.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !claims.isEmpty else { return false }

        let damages = analysis.estimatedDamages.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !damages.isEmpty else { return false }
        let damagesUnknown: Set<String> = ["n/a", "na", "to be assessed", "unknown", "none", "not applicable", "tbd", "n/a."]
        guard !damagesUnknown.contains(damages) else { return false }

        let files = caseTreeViewModel?.files(for: caseId, subfolder: .evidence) ?? []
        let memoryEvidence = CaseMemoryStore.shared.memoryOrEmpty(for: caseId).evidence
        let hasProof = !files.isEmpty || !memoryEvidence.isEmpty || !payload.evidenceItems.isEmpty
        return hasProof
    }

    private func maybeOfferAutonomousStrategy(
        caseId: UUID,
        payload: CaseUpdatePayload,
        latestUserText: String,
        userMessageCount: Int,
        assistantVisible: String
    ) {
        let normalized = latestUserText.lowercased()
        let userIntent = normalized.contains("i want to sue")
            || normalized.contains("what should i do")
            || normalized.contains("how do i")
            || normalized.contains("can i sue")
            || normalized.contains("how do i sue")
            || normalized.contains("i want to file")
            || normalized.contains("should i sue")

        let enoughFacts = userMessageCount >= 3
            && (!payload.extractedFacts.isEmpty || payload.caseType != nil)
            && (!payload.evidenceItems.isEmpty || !payload.timelineEvents.isEmpty || !payload.strategyNotes.isEmpty)

        let liabilityBundle = caseHasLiabilityDamagesEvidence(caseId: caseId, payload: payload)

        guard payload.shouldOfferStrategy || userIntent || enoughFacts || liabilityBundle else { return }
        guard stage(for: caseId) != .awaitingStrategyConsent && stage(for: caseId) != .awaitingProceedConsent else { return }
        guard lastStrategyOfferUserCount[caseId] != userMessageCount else { return }

        lastStrategyOfferUserCount[caseId] = userMessageCount

        let offerNeedle = "map out a strategy to pursue this"
        if !assistantVisible.localizedCaseInsensitiveContains(offerNeedle) {
            addLocalAssistantMessage("I can map out a strategy to pursue this. Want me to build that for you?", caseId: caseId)
        }
        setStage(.awaitingStrategyConsent, for: caseId)
    }

    private func enrichAutonomousTriggers(_ payload: inout CaseUpdatePayload, userMessage: Message, caseId: UUID) {
        let text = userMessage.content.lowercased()

        let admissionSignals = [
            "admitted", "he admitted", "she admitted", "they admitted", "boss admitted", "landlord admitted",
            "confessed", "i have texts", "i have text", "i have messages", "i have screenshots", "i have emails",
            "i have photos", "i recorded", "recording of", "i have proof", "witness saw", "signed a", "written admission"
        ]
        if admissionSignals.contains(where: { text.contains($0) }) {
            payload.shouldOfferEvidenceUpdate = true
            if payload.evidenceItems.isEmpty {
                payload.evidenceItems.append(
                    WorkflowEvidenceItem(
                        title: "Described admission, messages, or proof",
                        category: "Statements & media",
                        status: .have,
                        linkedMessageId: userMessage.id,
                        isTentative: true
                    )
                )
            }
        }

        if userMessageSuggestsTimeline(userMessage.content) {
            payload.shouldOfferTimelineUpdate = true
            if payload.timelineEvents.isEmpty {
                let desc = userMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
                payload.timelineEvents.append(CaseTimelineEvent(date: nil, description: desc))
            }
        }

        let turns = substantiveUserTurnCount(for: caseId)
        if turns >= 3 {
            payload.shouldOfferStrategy = true
            payload.shouldOfferDocumentChecklist = true
        }

        if ["i want to sue", "i want to file", "should i sue", "what should i do", "how do i sue"].contains(where: { text.contains($0) }) {
            payload.shouldOfferStrategy = true
            payload.shouldOfferDocumentChecklist = true
        }
    }

    private func userMessageSuggestsTimeline(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("deadline") || lower.contains("hearing") || lower.contains("filed") || lower.contains("served") { return true }
        if lower.contains("yesterday") || lower.contains("last week") || lower.contains("last month") || lower.contains("months ago") { return true }
        if lower.contains("today") || lower.contains("tomorrow") { return true }
        if text.range(of: #"\b20\d{2}\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"\b\d{1,2}/\d{1,2}"#, options: .regularExpression) != nil { return true }
        return false
    }

    private func sourceTextForCaseUpdates(caseId: UUID, fallback: String) -> String {
        let t = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        let shortAffirmations: Set<String> = ["yes", "y", "yeah", "sure", "ok", "okay", "please", "proceed", "no", "n", "nope", "not now"]
        if t.count < 14, shortAffirmations.contains(lower) {
            return messagesForCase(caseId: caseId)
                .reversed()
                .first { $0.role == "user" && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 }?
                .content
                ?? t
        }
        return t
    }

    private func autoApplyUserSignals(_ payload: CaseUpdatePayload, message: Message, caseId: UUID, userMessageCount: Int) {
        if payload.shouldOfferEvidenceUpdate {
            _ = applyEvidenceUpdate(
                caseId: caseId,
                sourceText: message.content,
                attachmentNames: message.attachmentNames,
                attachmentContents: message.attachmentContents
            )
        }

        if payload.shouldOfferTimelineUpdate {
            _ = applyTimelineUpdate(caseId: caseId, sourceText: message.content)
        }
    }

    private func autoApplyAssistantPayload(_ payload: CaseUpdatePayload, caseId: UUID, userMessageText: String, assistantVisible: String) {
        syncStructuredPayload(payload, into: caseId)

        let source = sourceTextForCaseUpdates(caseId: caseId, fallback: userMessageText)

        if payload.shouldOfferTimelineUpdate {
            _ = applyTimelineUpdate(caseId: caseId, sourceText: source)
        }

        if payload.shouldOfferEvidenceUpdate {
            _ = applyEvidenceUpdate(caseId: caseId, sourceText: source, attachmentNames: [], attachmentContents: [])
        }

        let userCount = messagesForCase(caseId: caseId).filter { $0.role == "user" }.count
        maybeOfferAutonomousStrategy(
            caseId: caseId,
            payload: payload,
            latestUserText: userMessageText,
            userMessageCount: userCount,
            assistantVisible: assistantVisible
        )
    }

    private func syncStructuredPayload(_ payload: CaseUpdatePayload, into caseId: UUID) {
        guard let tree = caseTreeViewModel else { return }

        if !payload.timelineEvents.isEmpty {
            for event in payload.timelineEvents {
                let title = String(event.description.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = event.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let exists = tree.events(for: caseId).contains {
                    $0.title.caseInsensitiveCompare(title.isEmpty ? "Timeline update" : title) == .orderedSame &&
                    ($0.summary ?? "").caseInsensitiveCompare(summary) == .orderedSame
                }
                if !exists {
                    tree.addTimelineEvent(
                        TimelineEvent(
                            kind: .response,
                            title: title.isEmpty ? "Timeline update" : title,
                            summary: summary.isEmpty ? nil : summary,
                            createdAt: Date(),
                            documentId: nil,
                            subfolder: .timeline
                        ),
                        caseId: caseId
                    )
                }
            }
        }

        if !payload.evidenceItems.isEmpty {
            let text = payload.evidenceItems.map { item in
                "• [\((item.status.rawValue).replacingOccurrences(of: "_", with: " "))] \(item.title)"
            }.joined(separator: "\n")
            _ = tree.upsertTextFile(caseId: caseId, subfolder: .evidence, name: "Evidence Registry", content: text)
        }

        if !payload.documentRequirements.isEmpty {
            let text = payload.documentRequirements.map { item in
                "• \(item.title) [\(item.urgency.rawValue)] [\(item.stage.rawValue)]"
            }.joined(separator: "\n")
            _ = tree.upsertTextFile(caseId: caseId, subfolder: .documents, name: "Document Checklist", content: text)
        }

        if !payload.strategyNotes.isEmpty {
            let text = payload.strategyNotes.map { note in
                "• \(note.category.rawValue): \(note.text)"
            }.joined(separator: "\n")
            _ = tree.upsertTextFile(caseId: caseId, subfolder: .history, name: "Strategy Notes", content: text)
        }

        if !payload.filingInstructions.isEmpty {
            let text = payload.filingInstructions.sorted { $0.stepOrder < $1.stepOrder }.map { item in
                "\(item.stepOrder). \(item.title)\n\(item.details)"
            }.joined(separator: "\n\n")
            _ = tree.upsertTextFile(caseId: caseId, subfolder: .documents, name: "Filing Instructions", content: text)
        }
    }

    private func normalizedCaseTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func targetCaseId(from normalizedText: String) -> UUID? {
        if let id = caseTreeViewModel?.cases.first(where: { folder in
            let title = normalizedCaseTitle(folder.title)
            return !title.isEmpty && normalizedText.contains(title)
        })?.id {
            return id
        }
        return targetCaseIdByOverlap(from: normalizedText)
    }

    /// Matches "the Smith case" / "Jones vs Smith folder" when the full title substring is not present.
    private func targetCaseIdByOverlap(from normalizedText: String) -> UUID? {
        guard let caseList = caseTreeViewModel?.cases else { return nil }
        let impliesCase = normalizedText.contains("case")
            || normalizedText.contains("matter")
            || normalizedText.contains("folder")
            || normalizedText.contains("file")
            || normalizedText.contains("lawsuit")
        guard impliesCase else { return nil }

        let userWords = significantWordsForCaseRouting(normalizedText)
        guard userWords.count >= 1 else { return nil }

        var best: (UUID, Int)?
        for folder in caseList {
            let titleWords = significantWordsForCaseRouting(normalizedCaseTitle(folder.title))
            guard !titleWords.isEmpty else { continue }
            let overlap = userWords.intersection(titleWords).count
            if overlap >= 1, best == nil || overlap > best!.1 {
                best = (folder.id, overlap)
            }
        }
        return best?.0
    }

    private func significantWordsForCaseRouting(_ text: String) -> Set<String> {
        let stop: Set<String> = [
            "the", "a", "an", "to", "for", "in", "on", "at", "and", "or", "my", "me", "we", "our",
            "this", "that", "these", "those", "add", "put", "update", "into", "from", "with", "about",
            "case", "matter", "folder", "file", "lawsuit", "pocket", "lawyer", "please", "just", "also",
            "vs", "v", "versus", "new", "here", "there", "photo", "image", "picture", "note", "document"
        ]
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stop.contains($0) }
        return Set(words)
    }

    private func looksLikeCrossCaseCommand(_ normalized: String) -> Bool {
        if normalized.contains("add ") || normalized.contains("update ") { return true }
        if normalized.contains("put this") || normalized.contains("put that") || normalized.contains("put it ") { return true }
        if normalized.contains("attach ") || normalized.contains("save to ") { return true }
        if normalized.contains("into ") && (normalized.contains("case") || normalized.contains("folder")) { return true }
        return false
    }

    private func reusableSourceText(for caseId: UUID, fallback: String) -> String {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedFallback.lowercased()
        let isCommandOnly = normalized.contains("add that") || normalized.contains("add this") || normalized.contains("add it") || normalized.contains("update the timeline")

        if !trimmedFallback.isEmpty && !isCommandOnly {
            return trimmedFallback
        }

        return messagesForCase(caseId: caseId)
            .reversed()
            .first(where: { $0.role == "user" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .content
            ?? trimmedFallback
    }

    @discardableResult
    private func applyHistoryUpdate(caseId: UUID, sourceText: String) -> UUID? {
        caseTreeViewModel?.addVersionedTextArtifact(
            caseId: caseId,
            subfolder: .history,
            baseName: "Case Notes",
            content: sourceText,
            responseTag: .note,
            timelineTitle: "Case notes updated",
            timelineSummary: sourceText.prefix(180).description
        )
    }

    @discardableResult
    private func applyTimelineUpdate(caseId: UUID, sourceText: String) -> UUID? {
        caseTreeViewModel?.addVersionedTextArtifact(
            caseId: caseId,
            subfolder: .timeline,
            baseName: "Live Timeline",
            content: sourceText,
            responseTag: .note,
            timelineTitle: "Timeline updated",
            timelineSummary: sourceText.prefix(180).description
        )
    }

    @discardableResult
    private func applyEvidenceUpdate(caseId: UUID, sourceText: String, attachmentNames: [String], attachmentContents: [String]) -> UUID? {
        let tree = caseTreeViewModel
        var lastFileId: UUID?

        if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastFileId = tree?.addVersionedTextArtifact(
                caseId: caseId,
                subfolder: .evidence,
                baseName: "Evidence List",
                content: sourceText,
                responseTag: .evidence,
                timelineTitle: "Evidence updated",
                timelineSummary: sourceText.prefix(180).description
            )
        }

        for (index, name) in attachmentNames.enumerated() {
            let attachmentText = index < attachmentContents.count ? attachmentContents[index] : ""
            let content = attachmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Attachment added: \(name)"
                : attachmentText
            lastFileId = tree?.addVersionedTextArtifact(
                caseId: caseId,
                subfolder: .evidence,
                baseName: name,
                content: content,
                responseTag: .evidence,
                timelineTitle: "Evidence added",
                timelineSummary: name
            )
        }

        return lastFileId
    }

    private func maybeOfferCaseUpdateSuggestion(for userMessage: Message, caseId: UUID) {
        guard pendingCaseUpdates[caseId] == nil else { return }
        guard lastSuggestedUpdateMessageIds[caseId] != userMessage.id else { return }
        let title = caseTreeViewModel?.cases.first(where: { $0.id == caseId })?.title ?? "this case"
        let payload = legalSignalExtractor.extract(
            from: userMessage.content,
            attachmentNames: userMessage.attachmentNames,
            attachmentContents: userMessage.attachmentContents,
            messageId: userMessage.id
        )

        if payload.shouldOfferEvidenceUpdate {
            pendingCaseUpdates[caseId] = .addToEvidence(
                caseId: caseId,
                sourceText: userMessage.content,
                attachmentNames: userMessage.attachmentNames,
                attachmentContents: userMessage.attachmentContents
            )
            pendingCaseUpdateCaseId = caseId
            lastSuggestedUpdateMessageIds[caseId] = userMessage.id
            addLocalAssistantMessage("Would you like me to add this to the evidence folder for \(title)?", caseId: caseId)
            return
        }

        if payload.shouldOfferTimelineUpdate {
            pendingCaseUpdates[caseId] = .updateTimeline(caseId: caseId, sourceText: userMessage.content)
            pendingCaseUpdateCaseId = caseId
            lastSuggestedUpdateMessageIds[caseId] = userMessage.id
            addLocalAssistantMessage("Would you like me to update the timeline for \(title)?", caseId: caseId)
        }
    }

    // MARK: - Single pipeline: typed, voice, and intake answers

    /// Single entry point for all user content (typed text, voice transcript, file message, or intake answer). Creates a user Message with optional attachments, stores it via addMessage (triggering CaseReasoningEngine and CaseAnalysis update), gets an AI reply and stores it, then optionally offers to resume intake. Use this for every user submission so all inputs flow through the same pipeline.
    func submitUserContent(
        content: String,
        caseId: UUID?,
        fileId: UUID? = nil,
        targetSubfolder: CaseSubfolder? = nil,
        intakePaused: Bool = false,
        attachmentNames: [String] = [],
        attachmentContents: [String] = []
    ) async -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !attachmentNames.isEmpty
        guard !trimmed.isEmpty || hasAttachments else { return nil }

        let existingUserMessageCount: Int = {
            guard let id = caseId else { return 0 }
            return messagesForCase(caseId: id).filter { $0.role == "user" }.count
        }()

        let message = Message(
            id: UUID(),
            caseId: caseId,
            fileId: fileId,
            role: "user",
            content: trimmed.isEmpty ? "(attachment)" : trimmed,
            timestamp: Date(),
            attachmentNames: attachmentNames,
            attachmentContents: attachmentContents
        )
        addMessage(message)
        print("🔥 submitUserContent user message count:", messages.count)

        if let id = caseId {
            var payload = legalSignalExtractor.extract(
                from: message.content,
                attachmentNames: message.attachmentNames,
                attachmentContents: message.attachmentContents,
                messageId: message.id
            )
            enrichAutonomousTriggers(&payload, userMessage: message, caseId: id)
            syncStructuredPayload(payload, into: id)
            autoApplyUserSignals(
                payload,
                message: message,
                caseId: id,
                userMessageCount: existingUserMessageCount + 1
            )
        }

        if let id = caseId {
            if existingUserMessageCount == 0 {
                CaseMemoryStore.shared.setMemory(CaseMemory(), forCaseId: id)
                CaseProgressStore.shared.markCompleted(caseId: id, stageTitle: "Asked first legal question")
                CaseProgressStore.shared.markCompleted(caseId: id, stageTitle: "Started example case")
            }

            let newInfo = effectiveUserContent(for: message)
            Task.detached { [weak self] in
                _ = try? await CaseMemoryStore.shared.updateMemory(caseId: id, newInformation: newInfo)
                await MainActor.run { self?.enqueueReasoning(caseId: id) }
            }
        }
        return await getAIReply(
            caseId: caseId,
            fileId: fileId,
            targetSubfolder: targetSubfolder,
            intakePaused: intakePaused
        )
    }

    /// Sends the last (user) message in the case to the AI with full conversation context, appends the assistant reply as a Message, and triggers CaseReasoningEngine via addMessage. If intakePaused is true, appends a follow-up message offering to resume intake and sets offeringResumeIntake. Call after addMessage(user Message). Attachment content is merged into the user message text for the API. Network call runs off the main actor; UI updates occur only when the response returns. Returns the AI response text or nil on failure.
    func getAIReply(caseId: UUID?, fileId: UUID?, targetSubfolder: CaseSubfolder? = nil, intakePaused: Bool = false) async -> String? {
        let caseMessages = messagesForCase(caseId: caseId)
        guard let last = caseMessages.last, last.role == "user" else { return nil }
        let previous = Array(caseMessages.dropLast())
        if let caseId {
            switch stage(for: caseId) {
            case .awaitingStrategyConsent:
                if let response = await handleStrategyConsentReply(last.content, caseId: caseId) {
                    return response
                }
            case .awaitingProceedConsent:
                if let response = await handleProceedConsentReply(last.content, caseId: caseId) {
                    return response
                }
            case .awaitingQuestionDecision:
                if let response = await handleQuestionDecisionReply(last.content, caseId: caseId) {
                    return response
                }
            case .awaitingDocumentConsent:
                if let response = await handleDocumentConsentReply(last.content, caseId: caseId) {
                    return response
                }
            case .openQuestionAnswer:
                if let response = await answerFollowUpQuestion(last.content, caseId: caseId) {
                    return response
                }
            case .initialSummary, .awaitingClarificationAnswers, .awaitingMoreClarificationAnswers, .awaitingFinalClarificationAnswers, .completed:
                break
            }
        }

        let request = requestForStage(
            stage(for: caseId),
            latestUserMessage: effectiveUserContent(for: last),
            caseId: caseId
        )
        let result = await runGuidedChatRequest(
            prompt: request.prompt,
            latestUserText: request.userText,
            previousMessages: previous,
            caseId: caseId
        )
        switch result {
        case .success(let response):
            let parsed = parseChatEnvelope(response)
            let visibleResponse = parsed.visibleResponse
            print("🔥 AI RESPONSE RECEIVED:", visibleResponse)
            await pauseBeforeReply(visibleResponse)
            let assistantMessage = appendAssistantResponse(
                visibleResponse,
                caseId: caseId,
                baseFileId: fileId,
                targetSubfolder: request.targetSubfolder
            )
            setStage(request.nextStage, for: caseId)

            if let caseId, let payload = parsed.payload {
                autoApplyAssistantPayload(
                    payload,
                    caseId: caseId,
                    userMessageText: last.content,
                    assistantVisible: visibleResponse
                )
            }

            NotificationCenter.default.post(
                name: .contextualMonetizationAIInteraction,
                object: nil,
                userInfo: [
                    "caseId": caseId?.uuidString ?? "",
                    "fileId": assistantMessage.fileId?.uuidString ?? ""
                ]
            )

            if intakePaused {
                addResumeIntakeOfferMessage(caseId: caseId, fileId: assistantMessage.fileId)
            }
            maybeOfferFolderSuggestion(caseId: caseId)
            return visibleResponse
        case .failure(let error):
            print("getAIReply failed:", error)
            let fallback = localEmergencyReply(for: last.content, caseId: caseId)
            await pauseBeforeReply(fallback)
            _ = appendAssistantResponse(
                fallback,
                caseId: caseId,
                baseFileId: fileId,
                targetSubfolder: targetSubfolder ?? .history
            )
            if let caseId {
                setStage(.awaitingClarificationAnswers, for: caseId)
            }
            return fallback
        }
    }

    private func responseTag(for subfolder: CaseSubfolder) -> ResponseTag {
        switch subfolder {
        case .evidence:
            return .evidence
        case .documents, .filedDocuments:
            return .draft
        case .response:
            return .strategy
        case .history, .timeline:
            return .note
        default:
            return .note
        }
    }

    private func fileType(for tag: ResponseTag) -> CaseFileType {
        switch tag {
        case .draft:
            return .docx
        case .evidence, .strategy, .note:
            return .note
        }
    }

    private func appendAssistantResponse(
        _ response: String,
        caseId: UUID?,
        baseFileId: UUID?,
        targetSubfolder: CaseSubfolder
    ) -> Message {
        let saved = saveAssistantResponseIntoActiveFolder(
            caseId: caseId,
            baseFileId: baseFileId,
            targetSubfolder: targetSubfolder,
            responseText: response
        )

        if let caseId, let newId = saved?.id, let idx = messages.lastIndex(where: { $0.caseId == caseId && $0.role == "user" }) {
            messages[idx].fileId = newId
        }

        let assistantMessage = Message(
            id: UUID(),
            caseId: caseId,
            fileId: saved?.id ?? baseFileId,
            role: "assistant",
            content: response,
            timestamp: Date(),
            responseTag: saved?.tag
        )
        addMessage(assistantMessage)
        print("🔥 getAIReply messages count after assistant append:", messages.count)
        return assistantMessage
    }

    private typealias GuidedReplyResult = Result<String, Error>

    private func localEmergencyReply(for userText: String, caseId: UUID?) -> String {
        let payload = legalSignalExtractor.extract(from: userText)
        let turnCount = caseId.map(substantiveUserTurnCount(for:)) ?? 1
        let plan = conversationPlanner.makePlan(payload: payload, userMessageCount: turnCount)
        let unanswered = unansweredFollowUpQuestions(for: caseId, latestUserMessage: userText, payload: payload)

        let normalized = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isDirect = isDirectLegalQuestion(userText)
            || normalized.contains("i want to sue")
            || normalized.contains("where do i file")
            || normalized.contains("what court")
        let mentionsEvidence = containsAny(
            normalized,
            ["screenshot", "screenshots", "email", "emails", "text", "texts", "recording", "recorded", "photo", "photos", "notice", "document", "bank statement"]
        )

        if isDirect {
            let overview = payload.caseType.map { "This looks most like a \($0.lowercased()) issue." }
                ?? "This may support a legal claim, but I’d still want a few key facts and documents before treating it as ready to file."
            let documents = payload.documentRequirements.prefix(3).map(\.title)
            let evidence = payload.evidenceItems.prefix(3).map(\.title)

            var lines: [String] = [overview]
            lines.append("Start by pulling together the strongest proof and the filing basics before you take action.")
            if !documents.isEmpty {
                lines.append("Main documents to gather next: \(documents.joined(separator: ", ")).")
            } else if !evidence.isEmpty {
                lines.append("Main proof to gather next: \(evidence.joined(separator: ", ")).")
            }
            lines.append("If you want, I can keep building this case step by step from here.")
            return lines.joined(separator: " ")
        }

        let lead = plan.summaryLead ?? "I’m still tracking this with you."
        let evidenceHint = payload.evidenceItems.first?.title ?? payload.documentRequirements.first?.title
        let nextQuestion = unanswered.first?.text

        var lines: [String] = [lead]
        if mentionsEvidence, let evidenceHint, !evidenceHint.isEmpty {
            lines.append("That evidence can matter a lot here, especially \(evidenceHint.lowercased()). I can help analyze or add it to the case.")
        } else if let evidenceHint, !evidenceHint.isEmpty, turnCount >= 2 {
            lines.append("One thing that would strengthen this quickly is \(evidenceHint.lowercased()).")
        }
        if let nextQuestion {
            lines.append(nextQuestion)
        } else {
            lines.append("If you want, I can turn this into a strategy, evidence list, or next-step plan.")
        }
        return lines.joined(separator: " ")
    }

    private func runGuidedChatRequest(
        prompt: String,
        latestUserText: String,
        previousMessages: [Message],
        caseId: UUID?
    ) async -> GuidedReplyResult {
        let chatMessage = ChatMessage(sender: .user, text: latestUserText)
        let messagesSnapshot = previousMessages
        let engineForNetwork = aiEngine
        let caseContext = caseId.map(buildAutonomousCaseContext(for:))
        let wantsStructuredOutput = caseId != nil
        return await Task.detached {
            do {
                let (response, _, _) = try await engineForNetwork.chat(
                    messages: [chatMessage],
                    previousMessages: messagesSnapshot,
                    systemPrompt: prompt,
                    caseContext: caseContext,
                    appendStructuredOutput: wantsStructuredOutput
                )
                return GuidedReplyResult.success(response)
            } catch {
                guard wantsStructuredOutput else {
                    return GuidedReplyResult.failure(error)
                }

                print("Structured guided chat failed, retrying without autonomous envelope:", error.localizedDescription)

                do {
                    let (fallbackResponse, _, _) = try await engineForNetwork.chat(
                        messages: [chatMessage],
                        previousMessages: messagesSnapshot,
                        systemPrompt: prompt,
                        caseContext: nil,
                        appendStructuredOutput: false
                    )
                    return GuidedReplyResult.success(fallbackResponse)
                } catch {
                    print("Plain guided chat failed, retrying without prior context:", error.localizedDescription)

                    do {
                        let (lastChanceResponse, _, _) = try await engineForNetwork.chat(
                            messages: [chatMessage],
                            previousMessages: nil,
                            systemPrompt: prompt,
                            caseContext: nil,
                            appendStructuredOutput: false
                        )
                        return GuidedReplyResult.success(lastChanceResponse)
                    } catch {
                        return GuidedReplyResult.failure(error)
                    }
                }
            }
        }.value
    }

    private func requestForStage(
        _ stage: GuidedCaseStage,
        latestUserMessage: String,
        caseId: UUID?
    ) -> (prompt: String, userText: String, targetSubfolder: CaseSubfolder, nextStage: GuidedCaseStage) {
        let directAnswerMode = isDirectLegalQuestion(latestUserMessage)
        let payload = legalSignalExtractor.extract(from: latestUserMessage)
        let missingFactsGuidance = promptGuidanceForMissingFacts(caseId: caseId, latestUserMessage: latestUserMessage, payload: payload)
        let directAnswerAddition = """

        Direct-question fast mode: answer immediately—no intake loop. Use numbered sections:
        1) Quick legal overview
        2) Step-by-step actions
        3) Documents needed
        4) Where to file
        Then end with exactly: “I can help you build this step-by-step inside your case if you want.”
        Still append VISIBLE RESPONSE + SYSTEM DATA (JSON) as required.
        """

        if directAnswerMode {
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(directAnswerAddition)
                \(missingFactsGuidance)

                Be specific and efficient. Populate SYSTEM DATA with any claims, evidence, timeline_events, and documents_to_generate implied by the question.
                """,
                userText: latestUserMessage,
                targetSubfolder: .response,
                nextStage: .completed
            )
        }

        switch stage {
        case .initialSummary:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(missingFactsGuidance)

                Stage: initial case intake.
                Use CASE CONTEXT; do not re-ask what is already captured there.
                Acknowledge what is new, name the most important legal angle so far, and ask at most one sharp follow-up only if a critical gap remains.
                Deliver one concrete insight every turn.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingClarificationAnswers
            )
        case .awaitingClarificationAnswers:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(missingFactsGuidance)

                Stage: continue fact gathering.
                Tie answers to CASE CONTEXT; never repeat prior questions.
                Ask one follow-up only if a material gap remains; otherwise advance to likely claims, proof plan, evidence significance, or next filings.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingMoreClarificationAnswers
            )
        case .awaitingMoreClarificationAnswers:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(missingFactsGuidance)

                Stage: deepen the record efficiently.
                Prefer summarizing what the case file now supports and listing the next proof or procedural step over generic Q&A.
                At most one follow-up if something essential is still missing.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingFinalClarificationAnswers
            )
        case .awaitingFinalClarificationAnswers:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(missingFactsGuidance)

                Stage: pivot from intake to action.
                Offer the next concrete legal move (preserve evidence, demand, agency charge, filing path) and invite a short strategy pass.
                Avoid yes/no dead-ends without guidance.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingStrategyConsent
            )
        case .completed:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(missingFactsGuidance)

                The user is in ongoing case Q&A.
                Answer the user's question briefly and practically in plain language.
                If appropriate, include steps, strategy, documents needed, and filing direction.
                End with one smart next question or one concrete next action.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingQuestionDecision
            )
        case .awaitingStrategyConsent, .awaitingProceedConsent, .awaitingQuestionDecision, .awaitingDocumentConsent, .openQuestionAnswer:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(missingFactsGuidance)
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: stage
            )
        }
    }

    private func normalizedDecision(_ text: String) -> Bool? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "y", "yeah", "sure", "ok", "okay", "please", "proceed"].contains(normalized) {
            return true
        }
        if ["no", "n", "not now", "nope"].contains(normalized) {
            return false
        }
        return nil
    }

    private func isDirectLegalQuestion(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let triggers = [
            "how do i",
            "what do i do",
            "can i sue",
            "what happens if",
            "what are my rights",
            "how do i sue",
            "i want to sue",
            "should i sue",
            "where do i file",
            "what court"
        ]
        return triggers.contains { normalized.contains($0) }
    }

    private func handleStrategyConsentReply(_ text: String, caseId: UUID) async -> String? {
        guard let decision = normalizedDecision(text) else { return nil }
        if decision == false {
            let content = "Okay. Tell me a little more about what happened, and I’ll keep building the case with you."
            _ = appendAssistantResponse(content, caseId: caseId, baseFileId: nil, targetSubfolder: .history)
            setStage(.awaitingMoreClarificationAnswers, for: caseId)
            return content
        }

        if let strategyResponse = await buildStrategyResponse(caseId: caseId) {
            await pauseBeforeReply(strategyResponse)
            _ = appendAssistantResponse(strategyResponse, caseId: caseId, baseFileId: nil, targetSubfolder: .response)
            setStage(.awaitingProceedConsent, for: caseId)
            return strategyResponse
        }

        let result = await runGuidedChatRequest(
            prompt: """
            \(AIEngine.guidedCaseChatSystemPrompt)

            Stage: strategy offer accepted.
            Give a clear primary strategy and a realistic secondary strategy.
            Keep it concise, practical, and easy to follow.
            Then ask whether the user wants to proceed.
            """,
            latestUserText: text,
            previousMessages: messagesForCase(caseId: caseId),
            caseId: caseId
        )
        guard case .success(let response) = result else { return nil }
        let parsed = parseChatEnvelope(response)
        let visibleResponse = parsed.visibleResponse
        await pauseBeforeReply(visibleResponse)
        _ = appendAssistantResponse(visibleResponse, caseId: caseId, baseFileId: nil, targetSubfolder: .response)
        if let payload = parsed.payload {
            autoApplyAssistantPayload(payload, caseId: caseId, userMessageText: text, assistantVisible: visibleResponse)
        }
        setStage(.awaitingProceedConsent, for: caseId)
        return visibleResponse
    }

    private func handleProceedConsentReply(_ text: String, caseId: UUID) async -> String? {
        guard let decision = normalizedDecision(text) else { return nil }
        if decision == false {
            let content = "Okay. We can pause there. Do you have any questions?"
            _ = appendAssistantResponse(content, caseId: caseId, baseFileId: nil, targetSubfolder: .history)
            setStage(.awaitingQuestionDecision, for: caseId)
            return content
        }

        let result = await runGuidedChatRequest(
            prompt: """
            \(AIEngine.guidedCaseChatSystemPrompt)

            Stage: proceed with the strategy.
            Give a short proceed plan with immediate next steps.
            Use plain language, stay practical, and keep it concise.
            Then ask whether the user has questions or wants help with the next deliverable.
            """,
            latestUserText: text,
            previousMessages: messagesForCase(caseId: caseId),
            caseId: caseId
        )
        guard case .success(let response) = result else { return nil }
        let parsed = parseChatEnvelope(response)
        let visibleResponse = parsed.visibleResponse
        await pauseBeforeReply(visibleResponse)
        _ = appendAssistantResponse(visibleResponse, caseId: caseId, baseFileId: nil, targetSubfolder: .response)
        if let payload = parsed.payload {
            autoApplyAssistantPayload(payload, caseId: caseId, userMessageText: text, assistantVisible: visibleResponse)
        }
        setStage(.awaitingQuestionDecision, for: caseId)
        return visibleResponse
    }

    private func handleQuestionDecisionReply(_ text: String, caseId: UUID) async -> String? {
        if let decision = normalizedDecision(text) {
            if decision {
                let content = "Ask your question. I'll keep it short and clear."
                await pauseBeforeReply(content)
                _ = appendAssistantResponse(content, caseId: caseId, baseFileId: nil, targetSubfolder: .history)
                setStage(.openQuestionAnswer, for: caseId)
                return content
            } else {
                let content = "Would you like me to list the main documents you should gather and add them to this folder?"
                await pauseBeforeReply(content)
                _ = appendAssistantResponse(content, caseId: caseId, baseFileId: nil, targetSubfolder: .documents)
                setStage(.awaitingDocumentConsent, for: caseId)
                return content
            }
        }

        return await answerFollowUpQuestion(text, caseId: caseId)
    }

    private func answerFollowUpQuestion(_ text: String, caseId: UUID) async -> String? {
        let result = await runGuidedChatRequest(
            prompt: """
            \(AIEngine.guidedCaseChatSystemPrompt)

            Stage: answer a follow-up question.
            Answer the user's question briefly and clearly based on the conversation so far.
            If appropriate, give steps, strategy, documents needed, and filing direction.
            End with either a smart next question or an offer to help with the next deliverable.
            """,
            latestUserText: text,
            previousMessages: messagesForCase(caseId: caseId),
            caseId: caseId
        )
        guard case .success(let response) = result else { return nil }
        let parsed = parseChatEnvelope(response)
        let visibleResponse = parsed.visibleResponse
        await pauseBeforeReply(visibleResponse)
        _ = appendAssistantResponse(visibleResponse, caseId: caseId, baseFileId: nil, targetSubfolder: .history)
        if let payload = parsed.payload {
            autoApplyAssistantPayload(payload, caseId: caseId, userMessageText: text, assistantVisible: visibleResponse)
        }
        setStage(.awaitingQuestionDecision, for: caseId)
        return visibleResponse
    }

    private func handleDocumentConsentReply(_ text: String, caseId: UUID) async -> String? {
        guard let decision = normalizedDecision(text) else { return nil }
        if decision == false {
            let content = "Okay. Ask me anything when you're ready."
            await pauseBeforeReply(content)
            _ = appendAssistantResponse(content, caseId: caseId, baseFileId: nil, targetSubfolder: .history)
            setStage(.completed, for: caseId)
            return content
        }

        let result = await runGuidedChatRequest(
            prompt: """
            \(AIEngine.guidedCaseChatSystemPrompt)

            Stage: documents needed.
            List the main documents or records the user should gather next.
            Keep the list focused, practical, and easy to understand.
            If helpful, group by what they likely already have versus what they still need.
            """,
            latestUserText: text,
            previousMessages: messagesForCase(caseId: caseId),
            caseId: caseId
        )
        guard case .success(let response) = result else { return nil }
        let parsed = parseChatEnvelope(response)
        let visibleResponse = parsed.visibleResponse
        await pauseBeforeReply(visibleResponse)
        _ = appendAssistantResponse(visibleResponse, caseId: caseId, baseFileId: nil, targetSubfolder: .documents)
        if let payload = parsed.payload {
            autoApplyAssistantPayload(payload, caseId: caseId, userMessageText: text, assistantVisible: visibleResponse)
        }
        setStage(.completed, for: caseId)
        return visibleResponse
    }

    private func buildStrategyResponse(caseId: UUID) async -> String? {
        guard let analysis = caseManager?.getCase(byId: caseId)?.analysis else { return nil }

        let evidenceFiles = caseTreeViewModel?.files(for: caseId, subfolder: .evidence) ?? []
        let evidenceSummaries = evidenceFiles.map {
            EvidenceAnalysis(
                summary: ($0.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? $0.content! : $0.name),
                violations: [],
                damages: nil,
                timelineEvents: [],
                deadlines: [],
                missingEvidence: []
            )
        }
        let timeline = analysis.timeline

        do {
            let strategy = try await aiEngine.updateLitigationStrategy(
                caseAnalysis: analysis,
                evidenceSummaries: evidenceSummaries,
                timeline: timeline
            )
            contextCache.update(CachedCaseContext(strategy: strategy), forCaseId: caseId)
            return formatLitigationStrategy(strategy) + "\n\nWould you like to proceed?"
        } catch {
            print("buildStrategyResponse failed:", error)
            return nil
        }
    }

    private func formatLitigationStrategy(_ strategy: LitigationStrategy) -> String {
        let primary = strategy.legalTheories.first ?? strategy.litigationPlan.first ?? "Build the strongest supported claim first."
        let secondary = strategy.legalTheories.dropFirst().first ?? strategy.opposingArguments.first ?? "Prepare for the likely defense and close obvious proof gaps."
        let nextSteps = Array(strategy.litigationPlan.prefix(3))
        let evidenceGap = strategy.evidenceGaps.first ?? strategy.weaknesses.first ?? "No major gap identified yet."

        var lines: [String] = []
        lines.append("Primary strategy: \(primary)")
        lines.append("Secondary strategy: \(secondary)")
        if !nextSteps.isEmpty {
            lines.append("Next steps:")
            for (index, step) in nextSteps.enumerated() {
                lines.append("\(index + 1). \(step)")
            }
        }
        lines.append("Important evidence gap: \(evidenceGap)")
        return lines.joined(separator: "\n")
    }

    private func maybeOfferFolderSuggestion(caseId: UUID?) {
        guard let caseId else { return }
        guard pendingFolderSuggestionCaseId == nil else { return }
        guard let folderTitle = caseTreeViewModel?.cases.first(where: { $0.id == caseId })?.title else { return }
        guard folderTitle == "General Law Questions" else { return }

        let userCount = messagesForCase(caseId: caseId).filter { $0.role == "user" }.count
        guard userCount > 0, userCount.isMultiple(of: 4) else { return }
        guard lastFolderSuggestionUserCount[caseId] != userCount else { return }

        lastFolderSuggestionUserCount[caseId] = userCount
        pendingFolderSuggestionCaseId = caseId
        addLocalAssistantMessage(
            "Would you like to start a new folder for this issue? Reply yes or no.",
            caseId: caseId
        )
    }

    /// Saves an AI reply into the active folder as a new versioned `CaseFile`.
    /// Returns the new file id (so the chat can point to it), or nil when it cannot be saved.
    @discardableResult
    private func saveAssistantResponseIntoActiveFolder(
        caseId: UUID?,
        baseFileId: UUID?,
        targetSubfolder: CaseSubfolder?,
        responseText: String
    ) -> (id: UUID, tag: ResponseTag)? {
        guard let caseId else { return nil }
        guard let tree = caseTreeViewModel else { return nil }

        let subfolder = targetSubfolder ?? tree.selectedSubfolder
        let tag = responseTag(for: subfolder)
        let newType = fileType(for: tag)

        let baseFile = baseFileId.flatMap { tree.file(for: caseId, subfolder: subfolder, fileId: $0) }
        let group = baseFile.map { tree.versionGroupBaseName(for: $0) } ?? tag.displayName
        let next = tree.nextVersionNumber(caseId: caseId, subfolder: subfolder, versionGroup: group)

        let newFileId = UUID()
        let newName = "\(group) v\(next)"

        let newFile = CaseFile(
            id: newFileId,
            name: newName,
            type: newType,
            relativePath: "",
            createdAt: Date(),
            caseId: caseId,
            recordingSubfolder: baseFile?.recordingSubfolder,
            content: responseText,
            durationSeconds: baseFile?.durationSeconds,
            responseTag: tag,
            versionGroupId: group,
            versionNumber: next
        )

        tree.addFile(caseId: caseId, subfolder: subfolder, file: newFile, content: responseText)

        // Update selection so chat is always tied to the saved artifact.
        tree.selectedSubfolder = subfolder
        tree.selectedFileId = newFileId

        let preview = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(220)

        let event = TimelineEvent(
            kind: .response,
            title: newName,
            summary: "AI saved (\(tag.displayName)): \(preview)",
            createdAt: Date(),
            documentId: newFileId,
            subfolder: subfolder
        )
        tree.addTimelineEvent(event, caseId: caseId)

        return (id: newFileId, tag: tag)
    }

    /// Builds the text sent to the AI: message content plus any attachment content (e.g. "[Attachment: name]\ncontent").
    private func effectiveUserContent(for message: Message) -> String {
        var parts: [String] = [message.content]
        if !message.attachmentNames.isEmpty {
            for (i, name) in message.attachmentNames.enumerated() {
                let content = i < message.attachmentContents.count ? message.attachmentContents[i] : ""
                if content.isEmpty {
                    parts.append("[Attachment: \(name)]")
                } else {
                    parts.append("[Attachment: \(name)]\n\(content)")
                }
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func addResumeIntakeOfferMessage(caseId: UUID?, fileId: UUID?) {
        let offerMessage = Message(
            id: UUID(),
            caseId: caseId,
            fileId: fileId,
            role: "assistant",
            content: "Would you like to continue with the intake interview? Tap “Resume intake” below or reply yes to continue.",
            timestamp: Date()
        )
        addMessage(offerMessage)
        offeringResumeIntake = true
    }

    /// Voice transcripts use the same pipeline as typed text and intake answers: Message → ConversationManager → CaseReasoningEngine → CaseAnalysis.
    func processVoiceStory(transcript: String, caseId: UUID?, intakePaused: Bool = false) async -> String? {
        await submitUserContent(content: transcript, caseId: caseId, intakePaused: intakePaused)
    }

    /// Snapshots case context on the main actor for use by the background reasoning loop. Fetches legal references if set, then builds context.
    private func snapshotContextForReasoning(caseId: UUID) async -> CaseContext? {
        let legalRefs = await legalResearchForCase?(caseId) ?? ""
        return buildCaseContext(caseId: caseId, legalReferencesAppendix: legalRefs.isEmpty ? nil : legalRefs)
    }

    /// Builds structured case context (case summary, messages, timeline, evidence, existing analysis, litigation strategy, optional legal references) via CaseContextBuilder for AI reasoning. Reuses cached case analysis and strategy when available; timeline, evidence, and recordings are always built from live data so the prompt is never stale. Messages are always fresh.
    private func buildCaseContext(caseId: UUID, legalReferencesAppendix: String? = nil) -> CaseContext {
        let caseMessages = messagesForCase(caseId: caseId)
        let timelineEvents = caseTreeViewModel?.events(for: caseId) ?? []
        let evidenceSummaries = liveEvidenceSummaries(caseId: caseId)
        let recordingTranscripts = liveRecordingTranscripts(caseId: caseId)
        let cached = contextCache.get(forCaseId: caseId)
        let caseAnalysis = cached?.caseAnalysis ?? caseManager?.getCase(byId: caseId)?.analysis
        let litigationStrategy = cached?.strategy

        let caseMemory = CaseMemoryStore.shared.memoryOrEmpty(for: caseId)
        return CaseContextBuilder.build(
            caseId: caseId,
            messages: caseMessages,
            timelineEvents: timelineEvents,
            evidenceSummaries: evidenceSummaries,
            recordingTranscripts: recordingTranscripts,
            caseAnalysis: caseAnalysis,
            litigationStrategy: litigationStrategy,
            legalReferencesAppendix: legalReferencesAppendix,
            caseMemory: caseMemory
        )
    }

    private func liveEvidenceSummaries(caseId: UUID) -> [String] {
        let tree = caseTreeViewModel
        let evidenceFiles = tree?.files(for: caseId, subfolder: .evidence) ?? []
        let selectedSubfolder = tree?.selectedSubfolder ?? .evidence
        let extraFiles = selectedSubfolder == .evidence ? [] : (tree?.files(for: caseId, subfolder: selectedSubfolder) ?? [])

        let makeSummary: (CaseFile, String) -> String = { file, prefix in
            let preview = (file.content?.trimmingCharacters(in: .whitespacesAndNewlines)).map { text in
                let maxLen = 2000
                return text.count <= maxLen ? text : String(text.prefix(maxLen)) + "..."
            } ?? "No text content"
            return "\(prefix) Document: \(file.name)\n\(preview)"
        }

        var summaries: [String] = []
        summaries.append(contentsOf: evidenceFiles.map { makeSummary($0, "Evidence:") })
        if !extraFiles.isEmpty {
            summaries.append(contentsOf: extraFiles.map { makeSummary($0, "Selected folder (\(selectedSubfolder.rawValue)):") })
        }
        return summaries
    }

    private func liveRecordingTranscripts(caseId: UUID) -> [String] {
        let recordingFiles = caseTreeViewModel?.files(for: caseId, subfolder: .recordings) ?? []
        return recordingFiles.compactMap { $0.content?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Enqueues a case reasoning job so it runs in the background. Use after evidence upload or other updates so the UI does not block. Analysis will appear when the job is processed and onCaseAnalysisUpdated will be called.
    func enqueueReasoning(caseId: UUID) {
        jobQueue.addJob(AIJob(id: UUID(), type: "case_reasoning", caseId: caseId))
        analyzingCaseIds.insert(caseId)
        ensureReasoningProcessorRunning()
    }

    /// Runs CaseReasoningEngine with CaseContext (built by CaseContextBuilder), then updates CaseAnalysis and notifies the UI. When legalResearchForCase is set, legal citations are included. Prefer the background job queue so the UI is not blocked; this method is used when a single refresh is needed off the queue.
    func refreshCaseAnalysis(caseId: UUID) async {
        analyzingCaseIds.insert(caseId)
        let legalRefs = await legalResearchForCase?(caseId) ?? ""
        let context = buildCaseContext(caseId: caseId, legalReferencesAppendix: legalRefs.isEmpty ? nil : legalRefs)
        let signature = CaseAnalysisResultCache.signature(
            messageCount: context.messages.count,
            timelineCount: context.timelineEvents.count,
            evidenceCount: context.evidenceSummaries.count,
            lastMessageId: context.messages.last?.id,
            memoryFingerprint: CaseContextBuilder.memoryFingerprint(context.caseMemory)
        )
        if let cached = analysisResultCache.get(signature: signature) {
            applyAnalysis(cached, caseId: caseId)
            return
        }
        guard let analysis = await caseReasoningEngine.updateCaseAnalysis(context: context, caseId: caseId) else { return }
        analysisResultCache.set(analysis, signature: signature)
        contextCache.update(
            CachedCaseContext(
                caseAnalysis: analysis,
                strategy: context.litigationStrategy,
                timelineEvents: context.timelineEvents,
                evidenceSummaries: context.evidenceSummaries,
                recordingTranscripts: context.recordingTranscripts
            ),
            forCaseId: caseId
        )
        applyAnalysis(analysis, caseId: caseId)
    }

    /// Applies analysis to case manager and notifies UI. Call on main only.
    private func applyAnalysis(_ analysis: CaseAnalysis, caseId: UUID) {
        if let title = caseTreeViewModel?.cases.first(where: { $0.id == caseId })?.title {
            caseManager?.ensureCaseExists(caseId: caseId, title: title)
        }
        caseManager?.setAnalysis(analysis, forCaseId: caseId)
        let memory = CaseMemoryStore.shared.memoryOrEmpty(for: caseId)
        let brief = caseBriefEngine.generateBrief(analysis: analysis, memory: memory)
        CaseBriefStore.shared.setBrief(brief, for: caseId)
        onCaseAnalysisUpdated?(caseId, analysis)
        analyzingCaseIds.remove(caseId)
    }

    // MARK: - Background reasoning queue (no UI delay while typing or recording)

    private func ensureReasoningProcessorRunning() {
        guard !isProcessingReasoning else { return }
        isProcessingReasoning = true
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.processReasoningQueueOffMain()
        }
    }

    /// Runs on a background executor; only reads/writes shared state via MainActor.
    private nonisolated func processReasoningQueueOffMain() async {
        while true {
            let job = await MainActor.run { [weak self] in self?.jobQueue.processNext() }
            guard let job = job, job.type == "case_reasoning" else {
                await MainActor.run { [weak self] in self?.isProcessingReasoning = false }
                return
            }
            let caseId = job.caseId
            // Build context on the MainActor (it reads actor state), but perform legal research off-actor.
            let legalResearch = await MainActor.run { [weak self] in self?.legalResearchForCase }
            let legalRefs = await legalResearch?(caseId) ?? ""
            let context: CaseContext? = await MainActor.run { [weak self] in
                guard let self else { return nil }
                return self.buildCaseContext(caseId: caseId, legalReferencesAppendix: legalRefs.isEmpty ? nil : legalRefs)
            }
            guard let context = context else { continue }

            // Signature touches cache inputs; compute under MainActor to satisfy Swift 6 isolation rules.
            let signature: String = await MainActor.run {
                CaseAnalysisResultCache.signature(
                    messageCount: context.messages.count,
                    timelineCount: context.timelineEvents.count,
                    evidenceCount: context.evidenceSummaries.count,
                    lastMessageId: context.messages.last?.id,
                    memoryFingerprint: CaseContextBuilder.memoryFingerprint(context.caseMemory)
                )
            }
            let cachedAnalysis = await MainActor.run { [weak self] in self?.analysisResultCache.get(signature: signature) }
            if let cached = cachedAnalysis {
                await MainActor.run { [weak self] in self?.applyAnalysis(cached, caseId: caseId) }
                continue
            }
            let analysis = await caseReasoningEngine.updateCaseAnalysis(context: context, caseId: caseId)
            guard let analysis = analysis else { continue }
            await MainActor.run { [weak self] in
                self?.analysisResultCache.set(analysis, signature: signature)
                self?.contextCache.update(
                    CachedCaseContext(
                        caseAnalysis: analysis,
                        strategy: context.litigationStrategy,
                        timelineEvents: context.timelineEvents,
                        evidenceSummaries: context.evidenceSummaries,
                        recordingTranscripts: context.recordingTranscripts
                    ),
                    forCaseId: caseId
                )
                self?.applyAnalysis(analysis, caseId: caseId)
            }
        }
    }
}
