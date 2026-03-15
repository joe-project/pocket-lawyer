import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false

    private let openAIService = OpenAIService()

    func sendCurrentMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendText(trimmed)
        inputText = ""
    }

    /// Send text (e.g. from voice transcription) and get AI response. Use for mic input.
    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMessage = ChatMessage(sender: .user, text: trimmed)
        messages.append(userMessage)
        isSending = true
        Task {
            do {
                let (response, offerDocument) = try await openAIService.sendChat(messages: messages)
                let aiMessage = ChatMessage(sender: .ai, text: response, isDocumentOffer: offerDocument)
                await MainActor.run {
                    messages.append(aiMessage)
                    isSending = false
                }
            } catch {
                let text: String
                if let workerError = error as? WorkerError {
                    text = workerError.localizedDescription
                } else {
                    text = error.localizedDescription.isEmpty ? "Sorry, something went wrong. Please try again." : error.localizedDescription
                }
                await MainActor.run {
                    messages.append(ChatMessage(sender: .ai, text: text))
                    isSending = false
                }
            }
        }
    }
}
