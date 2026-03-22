import Foundation

// MARK: - Case structure (entities linked by caseId)

/// Root case entity. All other entities reference this via caseId.
struct CaseEntity: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, description: String = "", createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
    }
}

/// A legal claim identified for the case. Linked by caseId.
struct Claim: Identifiable, Codable, Equatable {
    let id: UUID
    let caseId: UUID
    var text: String

    init(id: UUID = UUID(), caseId: UUID, text: String) {
        self.id = id
        self.caseId = caseId
        self.text = text
    }
}

/// Full case state for a single case. Aggregates all entities linked by caseId so the AI can reason over the complete case. Build this from CaseManager, ConversationManager, CaseTreeViewModel, etc.
struct CaseState: Identifiable {
    var id: UUID { caseId }
    let caseId: UUID
    var title: String
    var participants: [CaseParticipant]
    var messages: [Message]
    var evidence: [CaseFile]
    var timelineEvents: [TimelineEvent]
    var claims: [Claim]
    var documents: [CaseFile]
    var emailDrafts: [EmailDraft]
    var deadlines: [LegalDeadline]
    var litigationStrategy: LitigationStrategy?
    /// Parsed case analysis (summary, damages, next steps, etc.) when available.
    var analysis: CaseAnalysis?
    /// Confidence metrics when available (claim strength, evidence strength, etc.).
    var confidence: CaseConfidence?
    /// Evidence verification alerts (missing evidence, contradictions, timeline conflicts) when available.
    var evidenceAlerts: [EvidenceAlert]
    /// Structured legal arguments (IRAC) per claim when available.
    var legalArguments: [LegalArgument]

    init(
        caseId: UUID,
        title: String = "",
        participants: [CaseParticipant] = [],
        messages: [Message] = [],
        evidence: [CaseFile] = [],
        timelineEvents: [TimelineEvent] = [],
        claims: [Claim] = [],
        documents: [CaseFile] = [],
        emailDrafts: [EmailDraft] = [],
        deadlines: [LegalDeadline] = [],
        litigationStrategy: LitigationStrategy? = nil,
        analysis: CaseAnalysis? = nil,
        confidence: CaseConfidence? = nil,
        evidenceAlerts: [EvidenceAlert] = [],
        legalArguments: [LegalArgument] = []
    ) {
        self.caseId = caseId
        self.title = title
        self.participants = participants
        self.messages = messages
        self.evidence = evidence
        self.timelineEvents = timelineEvents
        self.claims = claims
        self.documents = documents
        self.emailDrafts = emailDrafts
        self.deadlines = deadlines
        self.litigationStrategy = litigationStrategy
        self.analysis = analysis
        self.confidence = confidence
        self.evidenceAlerts = evidenceAlerts
        self.legalArguments = legalArguments
    }
}
