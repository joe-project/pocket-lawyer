import Foundation
import Combine

/// A single pending attachment (name + optional text content for AI).
struct PendingAttachment: Identifiable {
    let id = UUID()
    let name: String
    let content: String
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    /// When true, the user is in the structured intake interview; sending a message pauses intake and the system will offer to resume after answering.
    @Published var isIntakeActive: Bool = false
    /// Latest case analysis parsed from an AI response; used to show CaseDashboardView under the chat.
    @Published var latestCaseAnalysis: CaseAnalysis?
    /// Attachments added via + that will be sent with the next message.
    @Published var pendingAttachments: [PendingAttachment] = []

    private let aiEngine: AIEngine
    private let conversationManager: ConversationManager
    private var cancellables = Set<AnyCancellable>()

    /// When set, timeline events extracted from AI responses are stored on this case.
    var caseManager: CaseManager?
    weak var workspace: WorkspaceManager?
    var selectedCaseId: UUID?
    /// Active file selected in the Legal OS sidebar (used to keep chat tied to a specific artifact).
    @Published var selectedFileId: UUID? = nil
    /// Active folder category selected in the Legal OS sidebar.
    @Published var selectedSubfolder: CaseSubfolder = .evidence

    init(
        aiEngine: AIEngine = .shared,
        conversationManager: ConversationManager
    ) {
        self.aiEngine = aiEngine
        self.conversationManager = conversationManager
        print("🔥 ChatViewModel INIT:", ObjectIdentifier(self))
        bindMessages()
    }

    private func bindMessages() {
        conversationManager.$messages
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { messages in
                print("🔥 ChatViewModel observed messages update:", messages.count)
            })
            .assign(to: &$messages)
    }

    /// Whether the user can send (has text and/or attachments and not currently sending).
    var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        return (hasText || hasAttachments) && !isSending
    }

    func sendCurrentMessage() {print("🔥 sendCurrentMessage CALLED")
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }

        let names = pendingAttachments.map(\.name)
        let contents = pendingAttachments.map(\.content)

        guard sendText(trimmed, attachmentNames: names, attachmentContents: contents) else {
            return
        }

        inputText = ""
        pendingAttachments.removeAll()
    }

    /// Inserts voice transcript into the input field (does not send). Call after stopping recording.
    func appendTranscriptToInput(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !inputText.isEmpty, !inputText.hasSuffix(" ") {
            inputText += " "
        }
        inputText += trimmed
    }

    /// Adds a file attachment to the next message. Content is optional (e.g. extracted text for documents).
    func addAttachment(name: String, content: String = "") {
        pendingAttachments.append(PendingAttachment(name: name, content: content))
    }

    /// Removes a pending attachment by id.
    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func clearPendingAttachments() {
        pendingAttachments = []
    }

    /// Submits a voice transcript through the same pipeline as typed text and intake answers (Message → ConversationManager → CaseReasoningEngine → CaseAnalysis). Call when recording finishes so the transcript is stored and the AI responds.
    func handleTranscript(_ transcript: String, caseId: UUID?) {
        Task {
            await MainActor.run { isSending = true }
            _ = await conversationManager.submitUserContent(
                content: transcript,
                caseId: caseId,
                fileId: selectedFileId,
                targetSubfolder: selectedSubfolder,
                intakePaused: isIntakeActive
            )
            if isIntakeActive { await MainActor.run { isIntakeActive = false } }
            await MainActor.run { isSending = false }
        }
    }

    /// Sends the transcript through `AIEngine` for analysis and returns the AI-generated legal insights (Case Plan, etc.). Network call runs off the main actor; UI updates occur only when the response returns.
    func analyzeStory(transcript: String) async throws -> String {
        isSending = true
        defer { isSending = false }
        let message = ChatMessage(sender: .user, text: transcript)
        let engine = aiEngine
        typealias ReplyResult = Result<(String, Bool, [CaseTimelineEvent]), Error>
        let task = Task.detached {
            do {
                let response = try await engine.chat(messages: [message])
                return ReplyResult.success(response)
            } catch {
                return ReplyResult.failure(error)
            }
        }
        let result: ReplyResult = await task.value
        let (response, _, timelineEvents) = try result.get()
        if let caseId = selectedCaseId, let manager = caseManager, !timelineEvents.isEmpty {
            manager.addTimelineEvents(timelineEvents, toCaseId: caseId)
        }
        let analysis = CaseAnalysisParser.parse(response)
        latestCaseAnalysis = analysis
        if let caseId = selectedCaseId, let manager = caseManager {
            manager.setAnalysis(analysis, forCaseId: caseId)
        }
        return response
    }

    /// Sends typed text and optional attachments through the shared pipeline: Message → ConversationManager → CaseReasoningEngine → CaseAnalysis. Same path as voice, file, and intake answers.
    @discardableResult
    func sendText(_ text: String, attachmentNames: [String] = [], attachmentContents: [String] = []) -> Bool {

        guard let workspace else {
            print("❌ Workspace unavailable")
            errorMessage = "The workspace is not ready yet."
            return false
        }

        guard let caseId = workspace.selectedCaseId else {
            print("❌ No case selected")
            errorMessage = "Select an active case before sending a message."
            return false
        }

        if handleFolderSuggestionReplyIfNeeded(text, currentCaseId: caseId, workspace: workspace) {
            return true
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !attachmentNames.isEmpty
        guard !trimmed.isEmpty || hasAttachments else { return false }

        errorMessage = nil
        isSending = true

        Task {
            let response = await conversationManager.submitUserContent(
                content: trimmed,
                caseId: caseId,
                fileId: selectedFileId,
                targetSubfolder: selectedSubfolder,
                intakePaused: isIntakeActive,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )

            await MainActor.run {
                if response == nil {
                    self.errorMessage = "Your message was saved to the case, but the AI response failed. Check the network/backend configuration and try again."
                }
                self.isSending = false
            }
        }
        return true
    }

    private func handleFolderSuggestionReplyIfNeeded(_ text: String, currentCaseId: UUID, workspace: WorkspaceManager) -> Bool {
        guard conversationManager.pendingFolderSuggestionCaseId == currentCaseId else { return false }

        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if ["yes", "y", "sure", "ok", "okay"].contains(normalized) {
            let title = conversationManager.suggestedFolderTitle(for: currentCaseId)
            let newCaseId = workspace.caseTreeViewModel.createNewCase(title: title, category: .mockCases)
            if let newFolder = workspace.caseTreeViewModel.cases.first(where: { $0.id == newCaseId }) {
                workspace.selectCase(byFolder: newFolder)
                workspace.caseTreeViewModel.selectedWorkspaceSection = .chat
                workspace.caseTreeViewModel.selectedSubfolder = .history
                workspace.caseTreeViewModel.selectedFileId = nil
                selectedCaseId = newCaseId
                selectedSubfolder = .history
                selectedFileId = nil
                conversationManager.clearPendingFolderSuggestion()
                conversationManager.addLocalAssistantMessage(
                    "Started a new folder: \(newFolder.title). Continue the conversation here.",
                    caseId: newCaseId
                )
                return true
            }
        }

        if ["no", "n", "not now"].contains(normalized) {
            conversationManager.clearPendingFolderSuggestion()
            conversationManager.addLocalAssistantMessage(
                "Okay, we’ll keep working in this folder.",
                caseId: currentCaseId
            )
            return true
        }

        return false
    }

    /// Call when the user chooses to resume the intake interview (e.g. after tapping "Resume intake").
    func resumeIntake() {
        isIntakeActive = true
        conversationManager.offeringResumeIntake = false
    }
}
