import Foundation

/// Guides the user through a structured legal intake interview with a fixed set of questions.
final class CaseIntakeEngine {

    static let questions: [IntakeQuestion] = [
        IntakeQuestion(id: UUID(), question: "Where did the incident occur? (state, county, or country)", category: "jurisdiction"),
        IntakeQuestion(id: UUID(), question: "When did the incident occur?", category: "timeline"),
        IntakeQuestion(id: UUID(), question: "Who was involved?", category: "parties"),
        IntakeQuestion(id: UUID(), question: "What happened?", category: "incident"),
        IntakeQuestion(id: UUID(), question: "Do you have any evidence?", category: "evidence"),
        IntakeQuestion(id: UUID(), question: "Were there witnesses?", category: "witnesses")
    ]

    /// Returns the next question after the given index, or nil if there is none.
    func nextQuestion(currentIndex: Int) -> IntakeQuestion? {
        guard currentIndex + 1 < Self.questions.count else { return nil }
        return Self.questions[currentIndex + 1]
    }
}
