import Foundation

// MARK: - Models

struct CaseProgressStage: Identifiable, Codable {
    let id: UUID
    let title: String
    var completed: Bool
}

struct CaseProgress: Codable {
    var stages: [CaseProgressStage]
}

// MARK: - Engine

/// Tracks the progress of a legal case through major stages (story recorded, claims identified, evidence added, demand letter, complaint filed, negotiation, settlement or trial).
final class CaseProgressEngine {

    func generateInitialProgress() -> CaseProgress {
        return CaseProgress(stages: [
            CaseProgressStage(id: UUID(), title: "Viewed case overview", completed: false),
            CaseProgressStage(id: UUID(), title: "Asked first legal question", completed: false),
            CaseProgressStage(id: UUID(), title: "Started example case", completed: false),
            CaseProgressStage(id: UUID(), title: "Create document", completed: false),
            CaseProgressStage(id: UUID(), title: "Upload evidence", completed: false),
            CaseProgressStage(id: UUID(), title: "File or take action", completed: false)
        ])
    }
}
