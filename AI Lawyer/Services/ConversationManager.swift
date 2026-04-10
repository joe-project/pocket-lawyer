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
        let base: UInt64 = 1_600_000_000
        let extra = min(UInt64(trimmedCount) * 4_000_000, 1_100_000_000)
        return base + extra
    }

    private func pauseBeforeReply(_ text: String) async {
        try? await Task.sleep(nanoseconds: responseDelayNanoseconds(for: text))
    }

    private func syncStructuredPayload(_ payload: CaseUpdatePayload, into caseId: UUID) {
        guard let tree = caseTreeViewModel else { return }

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
            let payload = legalSignalExtractor.extract(
                from: message.content,
                attachmentNames: message.attachmentNames,
                attachmentContents: message.attachmentContents,
                messageId: message.id
            )
            syncStructuredPayload(payload, into: id)
        }

        // First user submission for this case: create initial CaseMemory, update it with the new info, mark progress, and enqueue reasoning.
        if let id = caseId, existingUserMessageCount == 0 {
            CaseMemoryStore.shared.setMemory(CaseMemory(), forCaseId: id)
            CaseProgressStore.shared.markCompleted(caseId: id, stageTitle: "Asked first legal question")
            CaseProgressStore.shared.markCompleted(caseId: id, stageTitle: "Started example case")

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
            if let local = localGuidedReply(for: stage(for: caseId), caseId: caseId, latestUserMessage: last.content) {
                await pauseBeforeReply(local.content)
                let assistantMessage = appendAssistantResponse(
                    local.content,
                    caseId: caseId,
                    baseFileId: fileId,
                    targetSubfolder: local.targetSubfolder
                )
                setStage(local.nextStage, for: caseId)

                NotificationCenter.default.post(
                    name: .contextualMonetizationAIInteraction,
                    object: nil,
                    userInfo: [
                        "caseId": caseId.uuidString,
                        "fileId": assistantMessage.fileId?.uuidString ?? ""
                    ]
                )
                return local.content
            }

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
            latestUserMessage: effectiveUserContent(for: last)
        )
        let result = await runGuidedChatRequest(
            prompt: request.prompt,
            latestUserText: request.userText,
            previousMessages: previous
        )
        switch result {
        case .success(let response):
            print("🔥 AI RESPONSE RECEIVED:", response)
            await pauseBeforeReply(response)
            let assistantMessage = appendAssistantResponse(
                response,
                caseId: caseId,
                baseFileId: fileId,
                targetSubfolder: request.targetSubfolder
            )
            setStage(request.nextStage, for: caseId)

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
            if let caseId {
                maybeOfferCaseUpdateSuggestion(for: last, caseId: caseId)
            }
            return response
        case .failure(let error):
            print("getAIReply failed:", error)
            return nil
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

    private func runGuidedChatRequest(
        prompt: String,
        latestUserText: String,
        previousMessages: [Message]
    ) async -> GuidedReplyResult {
        let chatMessage = ChatMessage(sender: .user, text: latestUserText)
        let messagesSnapshot = previousMessages
        let engineForNetwork = aiEngine
        return await Task.detached {
            do {
                let (response, _, _) = try await engineForNetwork.chat(
                    messages: [chatMessage],
                    previousMessages: messagesSnapshot,
                    systemPrompt: prompt
                )
                return GuidedReplyResult.success(response)
            } catch {
                return GuidedReplyResult.failure(error)
            }
        }.value
    }

    private func requestForStage(
        _ stage: GuidedCaseStage,
        latestUserMessage: String
    ) -> (prompt: String, userText: String, targetSubfolder: CaseSubfolder, nextStage: GuidedCaseStage) {
        let directAnswerMode = isDirectLegalQuestion(latestUserMessage)
        let directAnswerAddition = """

        The user is asking a direct legal question. Answer immediately with clear steps, strategy, and documents needed. Do not ask multiple intake questions first.
        """

        if directAnswerMode {
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)
                \(directAnswerAddition)

                Give a practical answer right away. Use short sections or bullets if helpful. Be specific, efficient, and human. After answering, offer one concrete next action to help build the case.
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

                Stage: initial case intake.
                Respond naturally to what the user just shared.
                Briefly acknowledge it, identify what matters most so far, and ask 1-3 relevant follow-up questions if needed.
                Move the case forward instead of staying generic.
                No headers. No legalese. No repeated questions.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingClarificationAnswers
            )
        case .awaitingClarificationAnswers:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)

                Stage: continue fact gathering.
                Briefly acknowledge what the user answered.
                Ask 1-3 relevant follow-up questions only if they are still needed.
                If enough is already clear, start moving toward likely claims, strategy, or next steps instead of asking more basics.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingMoreClarificationAnswers
            )
        case .awaitingMoreClarificationAnswers:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)

                Stage: continue fact gathering.
                Briefly acknowledge the user's answers.
                Ask 1-3 relevant follow-up questions only if there are material gaps.
                If the factual picture is strong enough, start offering a short strategy or next action instead of looping intake.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingFinalClarificationAnswers
            )
        case .awaitingFinalClarificationAnswers:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)

                Stage: enough facts gathered for a first strategy.
                Briefly acknowledge the user and offer the next concrete action.
                Ask whether they want you to put together a short strategy for them.
                Keep it natural and concise.
                """,
                userText: latestUserMessage,
                targetSubfolder: .history,
                nextStage: .awaitingStrategyConsent
            )
        case .completed:
            return (
                prompt: """
                \(AIEngine.guidedCaseChatSystemPrompt)

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
                prompt: AIEngine.guidedCaseChatSystemPrompt,
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
            "what are my rights"
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

        let result = await runGuidedChatRequest(
            prompt: """
            \(AIEngine.guidedCaseChatSystemPrompt)

            Stage: strategy offer accepted.
            Give a clear primary strategy and a realistic secondary strategy.
            Keep it concise, practical, and easy to follow.
            Then ask whether the user wants to proceed.
            """,
            latestUserText: text,
            previousMessages: messagesForCase(caseId: caseId)
        )
        guard case .success(let response) = result else { return nil }
        await pauseBeforeReply(response)
        _ = appendAssistantResponse(response, caseId: caseId, baseFileId: nil, targetSubfolder: .response)
        setStage(.awaitingProceedConsent, for: caseId)
        return response
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
            previousMessages: messagesForCase(caseId: caseId)
        )
        guard case .success(let response) = result else { return nil }
        await pauseBeforeReply(response)
        _ = appendAssistantResponse(response, caseId: caseId, baseFileId: nil, targetSubfolder: .response)
        setStage(.awaitingQuestionDecision, for: caseId)
        return response
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
            previousMessages: messagesForCase(caseId: caseId)
        )
        guard case .success(let response) = result else { return nil }
        await pauseBeforeReply(response)
        _ = appendAssistantResponse(response, caseId: caseId, baseFileId: nil, targetSubfolder: .history)
        setStage(.awaitingQuestionDecision, for: caseId)
        return response
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
            previousMessages: messagesForCase(caseId: caseId)
        )
        guard case .success(let response) = result else { return nil }
        await pauseBeforeReply(response)
        _ = appendAssistantResponse(response, caseId: caseId, baseFileId: nil, targetSubfolder: .documents)
        setStage(.completed, for: caseId)
        return response
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
