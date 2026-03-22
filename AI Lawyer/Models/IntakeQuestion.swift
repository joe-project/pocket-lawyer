import Foundation

/// A single question in the structured legal intake interview.
struct IntakeQuestion: Identifiable {
    let id: UUID
    let question: String
    let category: String
}
