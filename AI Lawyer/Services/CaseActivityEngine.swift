import Foundation

/// Logs important events in a case. Each method creates a CaseActivity entry that can be stored per case (e.g. in CaseFolder or WorkspaceManager).
final class CaseActivityEngine {

    enum ActivityType: String {
        case storyRecorded = "story_recorded"
        case messageAdded = "message_added"
        case evidenceUploaded = "evidence_uploaded"
        case documentGenerated = "document_generated"
        case deadlineDetected = "deadline_detected"
        case emailDraftCreated = "email_draft_created"
    }

    /// Creates an activity entry when the user records a story (voice or intake).
    func createStoryRecorded() -> CaseActivity {
        CaseActivity(
            id: UUID(),
            title: "Story recorded",
            description: "User recorded or submitted their story.",
            timestamp: Date(),
            type: ActivityType.storyRecorded.rawValue
        )
    }

    /// Creates an activity entry when a message is added to the case chat.
    func createMessageAdded() -> CaseActivity {
        CaseActivity(
            id: UUID(),
            title: "Message added",
            description: "A new message was added to the case.",
            timestamp: Date(),
            type: ActivityType.messageAdded.rawValue
        )
    }

    /// Creates an activity entry when evidence is uploaded to the case.
    func createEvidenceUploaded(fileName: String? = nil) -> CaseActivity {
        let desc = fileName.map { "Evidence file added: \($0)." } ?? "Evidence was uploaded to the case."
        return CaseActivity(
            id: UUID(),
            title: "Evidence uploaded",
            description: desc,
            timestamp: Date(),
            type: ActivityType.evidenceUploaded.rawValue
        )
    }

    /// Creates an activity entry when a document is generated (e.g. demand letter, complaint).
    func createDocumentGenerated(documentName: String) -> CaseActivity {
        CaseActivity(
            id: UUID(),
            title: "Document generated",
            description: "Generated: \(documentName)",
            timestamp: Date(),
            type: ActivityType.documentGenerated.rawValue
        )
    }

    /// Creates an activity entry when a deadline is detected (e.g. from evidence analysis).
    func createDeadlineDetected(deadlineTitle: String) -> CaseActivity {
        CaseActivity(
            id: UUID(),
            title: "Deadline detected",
            description: deadlineTitle,
            timestamp: Date(),
            type: ActivityType.deadlineDetected.rawValue
        )
    }

    /// Creates an activity entry when an email draft is created for the case.
    func createEmailDraftCreated(subject: String? = nil) -> CaseActivity {
        let desc = subject.map { "Draft created: \($0)" } ?? "An email draft was created."
        return CaseActivity(
            id: UUID(),
            title: "Email draft created",
            description: desc,
            timestamp: Date(),
            type: ActivityType.emailDraftCreated.rawValue
        )
    }

    /// Creates a custom activity entry for other event types.
    func createActivity(type: String, title: String, description: String) -> CaseActivity {
        CaseActivity(
            id: UUID(),
            title: title,
            description: description,
            timestamp: Date(),
            type: type
        )
    }
}
