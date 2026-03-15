import Foundation
import Combine

class ConversationManager: ObservableObject {

    @Published var messages: [Message] = []

    func messagesForCase(caseId: UUID) -> [Message] {
        messages.filter { $0.caseId == caseId }
    }

    func addMessage(_ message: Message) {
        messages.append(message)
    }
}
