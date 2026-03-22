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
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    /// When true, the user is in the structured intake interview; sending a message pauses intake and the system will offer to resume after answering.
    @Published var isIntakeActive: Bool = false
    /// Latest case analysis parsed from an AI response; used to show CaseDashboardView under the chat.
    @Published var latestCaseAnalysis: CaseAnalysis?
    /// Attachments added via + that will be sent with the next message.
    @Published var pendingAttachments: [PendingAttachment] = []

    private let aiEngine: AIEngine
    /// When set, timeline events extracted from AI responses are stored on this case.
    var caseManager: CaseManager?
    var selectedCaseId: UUID?
    /// Active file selected in the Legal OS sidebar (used to keep chat tied to a specific artifact).
    @Published var selectedFileId: UUID? = nil
    /// Active folder category selected in the Legal OS sidebar.
    @Published var selectedSubfolder: CaseSubfolder = .evidence
    /// When set, voice transcripts are stored as messages via handleTranscript.
    var conversationManager: ConversationManager?

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    /// Whether the user can send (has text and/or attachments and not currently sending).
    var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        return (hasText || hasAttachments) && !isSending
    }

    func sendCurrentMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = pendingAttachments.map(\.name)
        let contents = pendingAttachments.map(\.content)
        guard !trimmed.isEmpty || !names.isEmpty else { return }
        sendText(trimmed, attachmentNames: names, attachmentContents: contents)
        inputText = ""
        pendingAttachments = []
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
        guard let conversationManager = conversationManager else { return }
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
        let aiMessage = ChatMessage(sender: .ai, text: response)
        messages.append(aiMessage)
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
    func sendText(_ text: String, attachmentNames: [String] = [], attachmentContents: [String] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !attachmentNames.isEmpty
        guard !trimmed.isEmpty || hasAttachments else { return }
        guard let conversationManager = conversationManager else { return }

        let intakeWasActive = isIntakeActive
        if intakeWasActive { isIntakeActive = false }

        isSending = true
        Task {
            _ = await conversationManager.submitUserContent(
                content: trimmed.isEmpty ? "" : trimmed,
                caseId: selectedCaseId,
                fileId: selectedFileId,
                targetSubfolder: selectedSubfolder,
                intakePaused: intakeWasActive,
                attachmentNames: attachmentNames,
                attachmentContents: attachmentContents
            )
            isSending = false
        }
    }

    /// Call when the user chooses to resume the intake interview (e.g. after tapping "Resume intake").
    func resumeIntake() {
        isIntakeActive = true
        conversationManager?.offeringResumeIntake = false
    }
}
