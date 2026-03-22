import Foundation

/// Generates professional legal email drafts related to the case. Does not send emails.
class EmailDraftEngine {

    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    func generateEmailDraft(caseAnalysis: CaseAnalysis, emailType: String) async throws -> EmailDraft {
        let prompt = """
        Generate a professional legal email.

        Type: \(emailType)

        Case summary:
        \(caseAnalysis.summary)

        Claims:
        \(caseAnalysis.claims.joined(separator: ", "))

        Include:
        • clear legal language
        • professional tone
        • suggested next steps
        """

        let chatMessage = ChatMessage(sender: .user, text: prompt)
        let (response, _, _) = try await aiEngine.chat(messages: [chatMessage])

        return EmailDraft(
            id: UUID(),
            subject: emailType,
            body: response,
            suggestedRecipient: nil,
            createdAt: Date()
        )
    }
}
