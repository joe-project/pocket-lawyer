import Foundation
import Combine

@MainActor
final class ConversationManager: ObservableObject {

    @Published var messages: [Message] = []
    /// True after answering a user question while intake was active; UI can show "Resume intake".
    @Published var offeringResumeIntake: Bool = false
    @Published private(set) var pendingFolderSuggestionCaseId: UUID?
    /// Case ids currently being analyzed by background reasoning (and/or awaiting AI pipeline completion).
    @Published private(set) var analyzingCaseIds: Set<UUID> = []

    private let aiEngine: AIEngine
    private let caseReasoningEngine: CaseReasoningEngine
    private let caseBriefEngine = CaseBriefEngine()
    private let messageBatcher = MessageBatcher()
    private let jobQueue = AIJobQueue()
    private let contextCache = CaseContextCache()
    private let analysisResultCache = CaseAnalysisResultCache()
    private var isProcessingReasoning = false
    private var lastFolderSuggestionUserCount: [UUID: Int] = [:]

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
        let effectiveContent = effectiveUserContent(for: last)
        let chatMessage = ChatMessage(sender: .user, text: effectiveContent)
        let messagesSnapshot = previous.isEmpty ? nil : previous
        let engineForNetwork = aiEngine
        typealias ReplyResult = Result<(String, Bool, [CaseTimelineEvent]), Error>
        let result: ReplyResult = await Task.detached {
            do {
                let response = try await engineForNetwork.chat(messages: [chatMessage], previousMessages: messagesSnapshot)
                return ReplyResult.success(response)
            } catch {
                return ReplyResult.failure(error)
            }
        }.value
        switch result {
        case .success(let (response, _, _)):
            print("🔥 AI RESPONSE RECEIVED:", response)
            // Persist the AI response into the selected folder as a new version.
            let saved: (id: UUID, tag: ResponseTag)? = saveAssistantResponseIntoActiveFolder(
                caseId: caseId,
                baseFileId: fileId,
                targetSubfolder: targetSubfolder,
                responseText: response
            )

            // Keep chat continuity: tie the triggering user message to the new saved version file
            // so the file-bound transcript shows the full exchange.
            if let newId = saved?.id {
                if let idx = messages.firstIndex(where: { $0.id == last.id }) {
                    messages[idx].fileId = newId
                }
            }

            let assistantMessage = Message(
                id: UUID(),
                caseId: caseId,
                fileId: saved?.id ?? fileId,
                role: "assistant",
                content: response,
                timestamp: Date(),
                responseTag: saved?.tag
            )
            addMessage(assistantMessage)
            print("🔥 getAIReply messages count after assistant append:", messages.count)

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
