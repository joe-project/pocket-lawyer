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

enum StructuredDeliverableCategory: String, Codable, CaseIterable {
    case timeline
    case evidence
    case documents
    case strategy
    case coaching
    case responses
    case decisionTreePathways
    case sayDontSay
}

struct WorkflowEvidenceItem: Identifiable, Codable, Hashable {
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

struct DecisionTreePathway: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var recommendedWhen: String
    var riskLevel: String
    var nextSteps: [String]
    var whenToUse: String
    var risks: [String]
    var expectedNextStep: String
    var keyEvidenceOrDocuments: [String]

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        recommendedWhen: String? = nil,
        riskLevel: String? = nil,
        nextSteps: [String] = [],
        whenToUse: String,
        risks: [String] = [],
        expectedNextStep: String,
        keyEvidenceOrDocuments: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description ?? whenToUse
        self.recommendedWhen = recommendedWhen ?? whenToUse
        self.riskLevel = riskLevel ?? "Unknown"
        self.nextSteps = nextSteps.isEmpty ? [expectedNextStep].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : nextSteps
        self.whenToUse = whenToUse
        self.risks = risks
        self.expectedNextStep = expectedNextStep
        self.keyEvidenceOrDocuments = keyEvidenceOrDocuments
    }
}

struct SayDontSayGuidance: Identifiable, Codable, Hashable {
    let id: UUID
    var say: [String]
    var dontSay: [String]
    var pitfalls: [String]
    var negotiationPitfalls: [String]
    var admissionsToAvoid: [String]
    var weakeningSideArguments: [String]

    init(
        id: UUID = UUID(),
        say: [String] = [],
        dontSay: [String] = [],
        pitfalls: [String] = [],
        negotiationPitfalls: [String] = [],
        admissionsToAvoid: [String] = [],
        weakeningSideArguments: [String] = []
    ) {
        self.id = id
        self.say = say
        self.dontSay = dontSay
        self.pitfalls = pitfalls
        self.negotiationPitfalls = negotiationPitfalls
        self.admissionsToAvoid = admissionsToAvoid
        self.weakeningSideArguments = weakeningSideArguments
    }
}

struct CoachingPoint: Identifiable, Codable, Hashable {
    let id: UUID
    var conversationPosture: String
    var presentFactsCleanly: String
    var gatherNext: [String]
    var stayOnMessage: String

    init(
        id: UUID = UUID(),
        conversationPosture: String,
        presentFactsCleanly: String,
        gatherNext: [String] = [],
        stayOnMessage: String
    ) {
        self.id = id
        self.conversationPosture = conversationPosture
        self.presentFactsCleanly = presentFactsCleanly
        self.gatherNext = gatherNext
        self.stayOnMessage = stayOnMessage
    }
}

struct ResponseAnalysis: Identifiable, Codable, Hashable {
    let id: UUID
    var sourceType: String
    var sourceParty: String?
    var summary: String
    var leveragePoints: [String]
    var risks: [String]
    var recommendedNextMoves: [String]
    var admittedPoints: [String]
    var deniedOrContestedPoints: [String]
    var deadlineFlags: [String]

    init(
        id: UUID = UUID(),
        sourceType: String,
        sourceParty: String? = nil,
        summary: String,
        leveragePoints: [String] = [],
        risks: [String] = [],
        recommendedNextMoves: [String] = [],
        admittedPoints: [String] = [],
        deniedOrContestedPoints: [String] = [],
        deadlineFlags: [String] = []
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceParty = sourceParty
        self.summary = summary
        self.leveragePoints = leveragePoints
        self.risks = risks
        self.recommendedNextMoves = recommendedNextMoves
        self.admittedPoints = admittedPoints
        self.deniedOrContestedPoints = deniedOrContestedPoints
        self.deadlineFlags = deadlineFlags
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

struct CaseUpdatePayload: Codable {
    var caseType: String?
    var jurisdictionHint: String?
    var summary: String?
    var extractedFacts: [ExtractedLegalFact]
    var timelineEvents: [CaseTimelineEvent]
    var evidenceItems: [WorkflowEvidenceItem]
    var documentRequirements: [DocumentRequirement]
    var filingInstructions: [FilingInstruction]
    var strategyNotes: [StrategyNote]
    var coachingPoints: [CoachingPoint]
    var decisionTreePathways: [DecisionTreePathway]
    var sayDontSayGuidance: [SayDontSayGuidance]
    var responseAnalyses: [ResponseAnalysis]
    var followUpQuestions: [FollowUpQuestion]
    var requestedActions: [String]
    var suggestedDeliverable: StructuredDeliverableCategory?
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
        evidenceItems: [WorkflowEvidenceItem] = [],
        documentRequirements: [DocumentRequirement] = [],
        filingInstructions: [FilingInstruction] = [],
        strategyNotes: [StrategyNote] = [],
        coachingPoints: [CoachingPoint] = [],
        decisionTreePathways: [DecisionTreePathway] = [],
        sayDontSayGuidance: [SayDontSayGuidance] = [],
        responseAnalyses: [ResponseAnalysis] = [],
        followUpQuestions: [FollowUpQuestion] = [],
        requestedActions: [String] = [],
        suggestedDeliverable: StructuredDeliverableCategory? = nil,
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
        self.coachingPoints = coachingPoints
        self.decisionTreePathways = decisionTreePathways
        self.sayDontSayGuidance = sayDontSayGuidance
        self.responseAnalyses = responseAnalyses
        self.followUpQuestions = followUpQuestions
        self.requestedActions = requestedActions
        self.suggestedDeliverable = suggestedDeliverable
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
