import Foundation

enum EvidenceStatus: String, Codable, CaseIterable {
    case have
    case need
    case requested
    case uploaded
    case addedToCase = "added_to_case"
    case tentative
}

enum DocumentUrgency: String, Codable, CaseIterable {
    case immediate
    case soon
    case later
}

enum DocumentStage: String, Codable, CaseIterable {
    case intake
    case evidence
    case filing
    case service
    case courtPrep = "court_prep"
    case followUp = "follow_up"
}

enum StrategyNoteCategory: String, Codable, CaseIterable {
    case priorityAction
    case risk
    case weakness
    case strength
    case contradiction
    case missingSupport
    case nextStep
}

enum LegalFactKind: String, Codable, CaseIterable {
    case person
    case date
    case location
    case claim
    case injury
    case evidence
    case deadline
    case caseType
    case requestedAction
    case document
    case venue
}

struct EvidenceItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var category: String
    var status: EvidenceStatus
    var notes: String?
    var linkedMessageId: UUID?
    var isTentative: Bool

    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        status: EvidenceStatus,
        notes: String? = nil,
        linkedMessageId: UUID? = nil,
        isTentative: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.status = status
        self.notes = notes
        self.linkedMessageId = linkedMessageId
        self.isTentative = isTentative
    }
}

struct DocumentRequirement: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var urgency: DocumentUrgency
    var stage: DocumentStage
    var notes: String?
    var sourceURL: String?
    var isTentative: Bool

    init(
        id: UUID = UUID(),
        title: String,
        urgency: DocumentUrgency,
        stage: DocumentStage,
        notes: String? = nil,
        sourceURL: String? = nil,
        isTentative: Bool = false
    ) {
        self.id = id
        self.title = title
        self.urgency = urgency
        self.stage = stage
        self.notes = notes
        self.sourceURL = sourceURL
        self.isTentative = isTentative
    }
}

struct FilingInstruction: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var details: String
    var jurisdiction: String?
    var sourceURL: String?
    var stepOrder: Int
    var isTentative: Bool

    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        jurisdiction: String? = nil,
        sourceURL: String? = nil,
        stepOrder: Int,
        isTentative: Bool = true
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.jurisdiction = jurisdiction
        self.sourceURL = sourceURL
        self.stepOrder = stepOrder
        self.isTentative = isTentative
    }
}

struct StrategyNote: Identifiable, Codable, Hashable {
    let id: UUID
    var category: StrategyNoteCategory
    var text: String
    var isTentative: Bool

    init(id: UUID = UUID(), category: StrategyNoteCategory, text: String, isTentative: Bool = false) {
        self.id = id
        self.category = category
        self.text = text
        self.isTentative = isTentative
    }
}

struct FollowUpQuestion: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var priority: Int
    var reason: String?

    init(id: UUID = UUID(), text: String, priority: Int = 0, reason: String? = nil) {
        self.id = id
        self.text = text
        self.priority = priority
        self.reason = reason
    }
}

struct ExtractedLegalFact: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: LegalFactKind
    var value: String
    var confidence: Double
    var isTentative: Bool

    init(id: UUID = UUID(), kind: LegalFactKind, value: String, confidence: Double = 0.5, isTentative: Bool = false) {
        self.id = id
        self.kind = kind
        self.value = value
        self.confidence = confidence
        self.isTentative = isTentative
    }
}

struct CaseUpdatePayload: Codable, Hashable {
    var caseType: String?
    var jurisdictionHint: String?
    var summary: String?
    var extractedFacts: [ExtractedLegalFact]
    var timelineEvents: [CaseTimelineEvent]
    var evidenceItems: [EvidenceItem]
    var documentRequirements: [DocumentRequirement]
    var filingInstructions: [FilingInstruction]
    var strategyNotes: [StrategyNote]
    var followUpQuestions: [FollowUpQuestion]
    var requestedActions: [String]
    var shouldOfferTimelineUpdate: Bool
    var shouldOfferEvidenceUpdate: Bool
    var shouldOfferDocumentChecklist: Bool
    var shouldOfferStrategy: Bool

    init(
        caseType: String? = nil,
        jurisdictionHint: String? = nil,
        summary: String? = nil,
        extractedFacts: [ExtractedLegalFact] = [],
        timelineEvents: [CaseTimelineEvent] = [],
        evidenceItems: [EvidenceItem] = [],
        documentRequirements: [DocumentRequirement] = [],
        filingInstructions: [FilingInstruction] = [],
        strategyNotes: [StrategyNote] = [],
        followUpQuestions: [FollowUpQuestion] = [],
        requestedActions: [String] = [],
        shouldOfferTimelineUpdate: Bool = false,
        shouldOfferEvidenceUpdate: Bool = false,
        shouldOfferDocumentChecklist: Bool = false,
        shouldOfferStrategy: Bool = false
    ) {
        self.caseType = caseType
        self.jurisdictionHint = jurisdictionHint
        self.summary = summary
        self.extractedFacts = extractedFacts
        self.timelineEvents = timelineEvents
        self.evidenceItems = evidenceItems
        self.documentRequirements = documentRequirements
        self.filingInstructions = filingInstructions
        self.strategyNotes = strategyNotes
        self.followUpQuestions = followUpQuestions
        self.requestedActions = requestedActions
        self.shouldOfferTimelineUpdate = shouldOfferTimelineUpdate
        self.shouldOfferEvidenceUpdate = shouldOfferEvidenceUpdate
        self.shouldOfferDocumentChecklist = shouldOfferDocumentChecklist
        self.shouldOfferStrategy = shouldOfferStrategy
    }
}

struct ConversationPlan {
    var summaryLead: String?
    var nextQuestions: [FollowUpQuestion]
    var shouldStayConversational: Bool
    var shouldOfferStrategy: Bool
    var shouldOfferDocuments: Bool
    var shouldOfferTimeline: Bool
}
