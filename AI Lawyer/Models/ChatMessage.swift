import Foundation

struct ChatMessage: Identifiable, Hashable {
    enum Sender {
        case user
        case ai
    }

    let id: UUID
    let sender: Sender
    let text: String
    let date: Date
    /// When true, the AI is offering to generate a document; show "Yes, generate" in UI.
    let isDocumentOffer: Bool

    init(id: UUID = UUID(), sender: Sender, text: String, date: Date = Date(), isDocumentOffer: Bool = false) {
        self.id = id
        self.sender = sender
        self.text = text
        self.date = date
        self.isDocumentOffer = isDocumentOffer
    }
}
