import Foundation

struct LegalSignalExtractor {
    func extract(
        from text: String,
        attachmentNames: [String] = [],
        attachmentContents: [String] = [],
        messageId: UUID? = nil
    ) -> CaseUpdatePayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        let caseType = detectCaseType(in: lower)
        let jurisdiction = detectJurisdiction(in: trimmed)
        let evidenceItems = detectEvidence(in: lower, attachmentNames: attachmentNames, messageId: messageId)
        let documentRequirements = detectDocumentRequirements(for: caseType, in: lower)
        let filingInstructions = detectFilingInstructions(for: caseType, jurisdiction: jurisdiction, in: lower)
        let strategyNotes = detectStrategyNotes(for: caseType, in: lower)
        let coachingPoints = detectCoachingPoints(for: caseType, in: lower)
        let decisionTreePathways = detectDecisionTreePathways(for: caseType, in: lower)
        let sayDontSayGuidance = detectSayDontSayGuidance(for: caseType, in: lower)
        let responseAnalyses = detectResponseAnalyses(in: trimmed, lower: lower, attachmentNames: attachmentNames)
        let requestedActions = detectRequestedActions(in: lower)
        let timelineEvents = detectTimelineEvents(in: trimmed)
        let facts = detectFacts(in: trimmed, caseType: caseType, jurisdiction: jurisdiction, requestedActions: requestedActions, evidenceItems: evidenceItems, timelineEvents: timelineEvents)
        let followUpQuestions = defaultFollowUpQuestions(for: caseType, lowerText: lower, jurisdiction: jurisdiction)
        let suggestedDeliverable = detectSuggestedDeliverable(
            lower: lower,
            evidenceItems: evidenceItems,
            documentRequirements: documentRequirements,
            decisionTreePathways: decisionTreePathways,
            sayDontSayGuidance: sayDontSayGuidance,
            coachingPoints: coachingPoints,
            responseAnalyses: responseAnalyses
        )

        return CaseUpdatePayload(
            caseType: caseType,
            jurisdictionHint: jurisdiction,
            summary: trimmed.isEmpty ? nil : trimmed,
            extractedFacts: facts,
            timelineEvents: timelineEvents,
            evidenceItems: evidenceItems,
            documentRequirements: documentRequirements,
            filingInstructions: filingInstructions,
            strategyNotes: strategyNotes,
            coachingPoints: coachingPoints,
            decisionTreePathways: decisionTreePathways,
            sayDontSayGuidance: sayDontSayGuidance,
            responseAnalyses: responseAnalyses,
            followUpQuestions: followUpQuestions,
            requestedActions: requestedActions,
            suggestedDeliverable: suggestedDeliverable,
            shouldOfferTimelineUpdate: !timelineEvents.isEmpty || lower.contains("deadline") || lower.contains("hearing"),
            shouldOfferEvidenceUpdate: !evidenceItems.isEmpty,
            shouldOfferDocumentChecklist: lower.contains("form") || lower.contains("document") || lower.contains("file"),
            shouldOfferStrategy: !followUpQuestions.isEmpty || lower.contains("what do i do") || lower.contains("strategy")
        )
    }

    private func detectCaseType(in lower: String) -> String? {
        if ["landlord", "tenant", "lease", "rent", "eviction", "apartment", "toilet", "repair"].contains(where: lower.contains) { return "landlord_tenant" }
        if ["work", "boss", "terminated", "fired", "paycheck", "hr", "harassment"].contains(where: lower.contains) { return "employment" }
        if ["car accident", "injury", "hospital", "medical", "police report"].contains(where: lower.contains) { return "injury_accident" }
        if ["protective order", "restraining order", "threat", "abuse", "served"].contains(where: lower.contains) { return "protection_order" }
        if ["criminal", "police", "charge", "arrest", "citation"].contains(where: lower.contains) { return "criminal_adjacent" }
        return nil
    }

    private func detectJurisdiction(in text: String) -> String? {
        let states = ["Texas", "California", "Florida", "New York", "Illinois", "Georgia", "Ohio"]
        return states.first(where: { text.localizedCaseInsensitiveContains($0) })
    }

    private func detectEvidence(in lower: String, attachmentNames: [String], messageId: UUID?) -> [WorkflowEvidenceItem] {
        var items: [WorkflowEvidenceItem] = []
        let mapping: [(String, String)] = [
            ("photo", "Photos"),
            ("image", "Photos"),
            ("screenshot", "Screenshots"),
            ("recording", "Recordings"),
            ("text", "Messages"),
            ("email", "Emails"),
            ("witness", "Witnesses"),
            ("police report", "Police Reports"),
            ("medical record", "Medical Records"),
            ("contract", "Contracts"),
            ("court filing", "Court Filings")
        ]

        for (keyword, category) in mapping where lower.contains(keyword) {
            items.append(WorkflowEvidenceItem(title: category, category: category, status: .need, linkedMessageId: messageId, isTentative: true))
        }

        for name in attachmentNames {
            items.append(WorkflowEvidenceItem(title: name, category: "Uploaded", status: .uploaded, linkedMessageId: messageId))
        }

        return Array(Set(items))
    }

    private func detectDocumentRequirements(for caseType: String?, in lower: String) -> [DocumentRequirement] {
        switch caseType {
        case "landlord_tenant":
            return [
                DocumentRequirement(title: "Lease agreement", urgency: .soon, stage: .evidence, notes: "Confirm repair and maintenance obligations", isTentative: true),
                DocumentRequirement(title: "Repair notice texts or emails", urgency: .immediate, stage: .evidence, notes: "Show notice to the landlord", isTentative: true),
                DocumentRequirement(title: "Rent payment proof", urgency: .soon, stage: .evidence, isTentative: true)
            ]
        case "protection_order":
            return [
                DocumentRequirement(title: "Petition or application", urgency: .immediate, stage: .filing, isTentative: true),
                DocumentRequirement(title: "Proof of service", urgency: .soon, stage: .service, isTentative: true)
            ]
        case "employment":
            return [
                DocumentRequirement(title: "Pay records", urgency: .soon, stage: .evidence, isTentative: true),
                DocumentRequirement(title: "HR complaints or emails", urgency: .soon, stage: .evidence, isTentative: true)
            ]
        default:
            if lower.contains("form") || lower.contains("document") {
                return [DocumentRequirement(title: "Required court or agency forms", urgency: .soon, stage: .filing, isTentative: true)]
            }
            return []
        }
    }

    private func detectFilingInstructions(for caseType: String?, jurisdiction: String?, in lower: String) -> [FilingInstruction] {
        guard lower.contains("file") || lower.contains("court") || lower.contains("serve") else { return [] }
        return [
            FilingInstruction(
                title: "Confirm filing venue",
                details: jurisdiction == nil ? "We still need the county, court, or state before filing instructions can be specific." : "Confirm the right court or agency before filing.",
                jurisdiction: jurisdiction,
                stepOrder: 1,
                isTentative: true
            ),
            FilingInstruction(
                title: "Check service requirements",
                details: "Before serving the other party, confirm who can serve, what must be attached, and any waiting period after filing.",
                jurisdiction: jurisdiction,
                stepOrder: 2,
                isTentative: true
            )
        ]
    }

    private func detectStrategyNotes(for caseType: String?, in lower: String) -> [StrategyNote] {
        switch caseType {
        case "landlord_tenant":
            return [
                StrategyNote(category: .priorityAction, text: "Lock down the repair timeline and written notice trail first.", isTentative: true),
                StrategyNote(category: .missingSupport, text: "We need proof of notice, the lease, and evidence of the living conditions.", isTentative: true)
            ]
        case "protection_order":
            return [
                StrategyNote(category: .priorityAction, text: "Identify the filing court, service status, and any immediate safety deadlines.", isTentative: true)
            ]
        default:
            if lower.contains("help") || lower.contains("what do i do") {
                return [StrategyNote(category: .nextStep, text: "Clarify the timeline, core documents, and venue before strategy hardens.", isTentative: true)]
            }
            return []
        }
    }

    private func detectCoachingPoints(for caseType: String?, in lower: String) -> [CoachingPoint] {
        guard lower.contains("coach") || lower.contains("how should i say") || lower.contains("how do i explain") || lower.contains("what do i say") || lower.contains("conversation") else {
            return []
        }

        switch caseType {
        case "landlord_tenant":
            return [
                CoachingPoint(
                    conversationPosture: "Stay calm, specific, and focused on the repair problem and notice history.",
                    presentFactsCleanly: "Lead with the dates, the broken condition, the written notice, and the impact on daily living.",
                    gatherNext: ["photos of conditions", "repair requests", "rent records"],
                    stayOnMessage: "Keep bringing the conversation back to habitability, written notice, and a clear fix deadline."
                )
            ]
        default:
            return [
                CoachingPoint(
                    conversationPosture: "Stay factual, calm, and hard to sidetrack.",
                    presentFactsCleanly: "Use a simple timeline and only the strongest supported facts.",
                    gatherNext: ["core documents", "messages", "timeline anchors"],
                    stayOnMessage: "Repeat the core issue, the proof, and the concrete outcome you want."
                )
            ]
        }
    }

    private func detectDecisionTreePathways(for caseType: String?, in lower: String) -> [DecisionTreePathway] {
        let forceCaseBuilding = lower.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count >= 45
            || ["scared", "afraid", "threat", "abuse", "unsafe", "sue", "court", "file", "eviction", "insurance", "protective order", "restraining order"].contains(where: lower.contains)
        guard lower.contains("decision tree")
            || lower.contains("pathway")
            || lower.contains("path")
            || lower.contains("options")
            || lower.contains("settle")
            || lower.contains("mediate")
            || lower.contains("file")
            || forceCaseBuilding else {
            return []
        }

        switch caseType {
        case "landlord_tenant":
            return [
                DecisionTreePathway(
                    title: "Negotiation path",
                    whenToUse: "Use this when you have written notice and want repairs, rent relief, or a settlement before filing.",
                    risks: ["Landlord delays", "Promises with no action"],
                    expectedNextStep: "Send a clean written demand tied to the repair history and your requested fix date.",
                    keyEvidenceOrDocuments: ["repair emails/texts", "photos", "lease"]
                ),
                DecisionTreePathway(
                    title: "Mediation path",
                    whenToUse: "Use this when both sides are still communicating and you want a neutral process before filing.",
                    risks: ["Agreement can be vague", "Delays if no enforceable terms"],
                    expectedNextStep: "Prepare a one-page fact timeline and settlement terms before mediation.",
                    keyEvidenceOrDocuments: ["timeline summary", "repair proof bundle", "proposed settlement terms"]
                ),
                DecisionTreePathway(
                    title: "Direct filing path",
                    whenToUse: "Use this when notice is strong, conditions are serious, and informal requests are going nowhere.",
                    risks: ["Venue mistakes", "Weak damages proof"],
                    expectedNextStep: "Confirm court/agency venue and assemble the filing packet.",
                    keyEvidenceOrDocuments: ["lease", "notice trail", "photos", "damages proof"]
                ),
                DecisionTreePathway(
                    title: "Evidence-first path",
                    whenToUse: "Use this when the facts are promising but the proof file is still thin.",
                    risks: ["Delay", "Conditions change before documented"],
                    expectedNextStep: "Lock down dated photos, written notice, witness support, and costs.",
                    keyEvidenceOrDocuments: ["photos", "repair timeline", "receipts", "witness notes"]
                ),
                DecisionTreePathway(
                    title: "Wait-for-response path",
                    whenToUse: "Use this when you just sent a demand and there is still a reasonable response window.",
                    risks: ["Deadlines can slip", "Other side reframes facts"],
                    expectedNextStep: "Set a hard response date and prepare escalation if they fail to cure.",
                    keyEvidenceOrDocuments: ["sent demand letter", "delivery proof", "deadline tracker"]
                ),
                DecisionTreePathway(
                    title: "Escalation path",
                    whenToUse: "Use this when promised fixes fail or new violations occur after notice.",
                    risks: ["Relationship breakdown", "Counter-claims"],
                    expectedNextStep: "Escalate to agency/court route with a clean evidence packet and chronology.",
                    keyEvidenceOrDocuments: ["follow-up notices", "updated photos", "prior promises in writing"]
                )
            ]
        default:
            return [
                DecisionTreePathway(
                    title: "Evidence-gathering-first path",
                    whenToUse: "Use this when the issue is real but the proof or venue is still unclear.",
                    risks: ["Delay", "facts staying too broad"],
                    expectedNextStep: "Tighten the timeline, documents, and strongest supporting records first.",
                    keyEvidenceOrDocuments: ["timeline", "messages", "core documents"]
                ),
                DecisionTreePathway(
                    title: "Direct filing path",
                    whenToUse: "Use this when the claim, venue, and proof set are already concrete enough to act.",
                    risks: ["Filing in the wrong place", "missing attachments"],
                    expectedNextStep: "Confirm filing location and required forms before filing.",
                    keyEvidenceOrDocuments: ["petition/complaint", "supporting proof", "service documents"]
                ),
                DecisionTreePathway(
                    title: "Negotiation path",
                    whenToUse: "Use this when liability is arguable and early resolution can preserve leverage and cost.",
                    risks: ["Low-ball positioning", "Loose language that weakens later filing posture"],
                    expectedNextStep: "Send a concise position statement with proof anchors and requested resolution.",
                    keyEvidenceOrDocuments: ["core evidence packet", "damages summary", "demand draft"]
                ),
                DecisionTreePathway(
                    title: "Mediation path",
                    whenToUse: "Use this when parties are stuck but still willing to discuss structured resolution.",
                    risks: ["Non-binding outcome", "Premature concessions"],
                    expectedNextStep: "Define acceptable terms and non-negotiables before the session.",
                    keyEvidenceOrDocuments: ["position summary", "term sheet", "supporting exhibits"]
                ),
                DecisionTreePathway(
                    title: "Wait-for-response path",
                    whenToUse: "Use this when a response is expected soon and immediate filing is unnecessary.",
                    risks: ["Missed deadlines", "Evidence staleness"],
                    expectedNextStep: "Track deadlines and prepare escalation package in parallel.",
                    keyEvidenceOrDocuments: ["sent correspondence", "calendar deadlines", "draft escalation packet"]
                ),
                DecisionTreePathway(
                    title: "Escalation path",
                    whenToUse: "Use this when the other side denies responsibility or misses response windows.",
                    risks: ["Higher cost", "Procedural complexity"],
                    expectedNextStep: "Move to formal filing/agency action with finalized evidence and venue check.",
                    keyEvidenceOrDocuments: ["final timeline", "admissions/denials log", "filing checklist"]
                )
            ]
        }
    }

    private func detectSayDontSayGuidance(for caseType: String?, in lower: String) -> [SayDontSayGuidance] {
        guard lower.contains("don't say")
            || lower.contains("dont say")
            || lower.contains("what not to say")
            || lower.contains("what should i say")
            || lower.contains("adjuster")
            || lower.contains("negotiate") else {
            return []
        }

        switch caseType {
        case "landlord_tenant":
            return [
                SayDontSayGuidance(
                    say: [
                        "State the repair issue, the notice history, and the specific fix or compensation you want.",
                        "Ask for written confirmation and a deadline."
                    ],
                    dontSay: [
                        "Do not exaggerate facts you cannot prove.",
                        "Do not volunteer that the problem is minor or already resolved if it is not."
                    ],
                    pitfalls: [
                        "Getting pulled into side disputes about unrelated lease issues.",
                        "Making emotional admissions that distract from the repair timeline and notice trail."
                    ],
                    negotiationPitfalls: [
                        "Accepting verbal promises without written terms or deadlines.",
                        "Conceding rent or damages numbers before reviewing your proof set."
                    ],
                    admissionsToAvoid: [
                        "Admitting the problem was minor if photos and timeline show serious impact.",
                        "Admitting you never gave notice if written messages exist."
                    ],
                    weakeningSideArguments: [
                        "Bringing unrelated roommate or personality disputes into repair negotiations."
                    ]
                )
            ]
        default:
            return [
                SayDontSayGuidance(
                    say: [
                        "Keep the message short, factual, and tied to your strongest proof.",
                        "Ask for a specific response or next step in writing."
                    ],
                    dontSay: [
                        "Do not guess at facts you are unsure about.",
                        "Do not make admissions that undercut your own timeline or damages."
                    ],
                    pitfalls: [
                        "Arguing every side issue instead of the main supported point.",
                        "Using broad accusations when a narrow factual statement is stronger."
                    ],
                    negotiationPitfalls: [
                        "Trading away leverage before getting written counterparty commitments.",
                        "Letting urgency force unclear settlement terms."
                    ],
                    admissionsToAvoid: [
                        "Admitting uncertainty about key dates without checking records first.",
                        "Admitting no damages before finishing a losses inventory."
                    ],
                    weakeningSideArguments: [
                        "Overstating side claims that are not supported by documents."
                    ]
                )
            ]
        }
    }

    private func detectResponseAnalyses(in text: String, lower: String, attachmentNames: [String]) -> [ResponseAnalysis] {
        let looksLikeResponse = lower.contains("they responded")
            || lower.contains("response letter")
            || lower.contains("response email")
            || lower.contains("adjuster")
            || lower.contains("denied")
            || lower.contains("rejected")
            || lower.contains("landlord said")
            || lower.contains("insurance said")
            || lower.contains("court said")
            || lower.contains("agency said")
            || lower.contains("opposing counsel")
            || lower.contains("response attached")
            || lower.contains("attached response")
            || attachmentNames.contains(where: { $0.lowercased().contains("response") || $0.lowercased().contains("letter") || $0.lowercased().contains("email") })

        guard looksLikeResponse else { return [] }

        let sourceType: String
        if lower.contains("adjuster") || lower.contains("insurance") {
            sourceType = "Insurance response"
        } else if lower.contains("landlord") {
            sourceType = "Landlord response"
        } else if lower.contains("court") {
            sourceType = "Court response"
        } else if lower.contains("agency") {
            sourceType = "Agency response"
        } else {
            sourceType = "Incoming response"
        }

        return [
            ResponseAnalysis(
                sourceType: sourceType,
                sourceParty: sourceType.replacingOccurrences(of: " response", with: ""),
                summary: text,
                leveragePoints: ["Look for admissions, timeline concessions, or reasons they gave in writing."],
                risks: ["Watch for deadline language, denials, or partial admissions that narrow your options."],
                recommendedNextMoves: ["Pull out the exact admissions or denials.", "Match the response against your timeline and proof."],
                admittedPoints: ["Capture any statement that confirms your timeline, notice, or losses."],
                deniedOrContestedPoints: ["List each denial and tie it to contradictory proof."],
                deadlineFlags: ["Check the response for any response deadlines, hearing dates, or cure windows."]
            )
        ]
    }

    private func detectRequestedActions(in lower: String) -> [String] {
        ["add this to the case", "add this as evidence", "put this under timeline", "attach this", "what documents do i need", "where do i file this", "what should i print", "what do i serve first"]
            .filter { lower.contains($0) }
    }

    private func detectSuggestedDeliverable(
        lower: String,
        evidenceItems: [WorkflowEvidenceItem],
        documentRequirements: [DocumentRequirement],
        decisionTreePathways: [DecisionTreePathway],
        sayDontSayGuidance: [SayDontSayGuidance],
        coachingPoints: [CoachingPoint],
        responseAnalyses: [ResponseAnalysis]
    ) -> StructuredDeliverableCategory? {
        if !responseAnalyses.isEmpty { return .responses }
        if !sayDontSayGuidance.isEmpty { return .sayDontSay }
        if !decisionTreePathways.isEmpty { return .decisionTreePathways }
        if !coachingPoints.isEmpty { return .coaching }
        if lower.contains("strategy") || lower.contains("what should i do") || lower.contains("how do i sue") { return .strategy }
        if lower.contains("timeline") || lower.contains("deadline") || lower.contains("hearing") { return .timeline }
        if !documentRequirements.isEmpty { return .documents }
        if !evidenceItems.isEmpty { return .evidence }
        return nil
    }

    private func detectTimelineEvents(in text: String) -> [CaseTimelineEvent] {
        let lower = text.lowercased()
        guard lower.contains("today") || lower.contains("yesterday") || lower.contains("deadline") || lower.contains("hearing") || lower.contains("served") || lower.contains("filed") else {
            return []
        }
        return [CaseTimelineEvent(date: nil, description: text)]
    }

    private func detectFacts(
        in text: String,
        caseType: String?,
        jurisdiction: String?,
        requestedActions: [String],
        evidenceItems: [WorkflowEvidenceItem],
        timelineEvents: [CaseTimelineEvent]
    ) -> [ExtractedLegalFact] {
        var facts: [ExtractedLegalFact] = []
        if let caseType {
            facts.append(ExtractedLegalFact(kind: .caseType, value: caseType, confidence: 0.8))
        }
        if let jurisdiction {
            facts.append(ExtractedLegalFact(kind: .location, value: jurisdiction, confidence: 0.75))
        }
        for action in requestedActions {
            facts.append(ExtractedLegalFact(kind: .requestedAction, value: action, confidence: 0.9))
        }
        for item in evidenceItems {
            facts.append(ExtractedLegalFact(kind: .evidence, value: item.title, confidence: 0.7, isTentative: item.isTentative))
        }
        for event in timelineEvents {
            facts.append(ExtractedLegalFact(kind: .date, value: event.description, confidence: 0.55, isTentative: event.date == nil))
        }
        if !text.isEmpty {
            facts.append(ExtractedLegalFact(kind: .claim, value: text, confidence: 0.35, isTentative: true))
        }
        return facts
    }

    private func defaultFollowUpQuestions(for caseType: String?, lowerText: String, jurisdiction: String?) -> [FollowUpQuestion] {
        let hasTimeline = ["month", "months", "week", "weeks", "day", "days", "since", "for ", "today", "yesterday", "three months"].contains(where: lowerText.contains)
        let hasWrittenNotice = ["email", "emailed", "text", "texts", "message", "messages", "called", "notice", "wrote", "letter"].contains(where: lowerText.contains)
        let hasLease = ["lease", "rental agreement", "tenant", "rent"].contains(where: lowerText.contains)
        let hasDamageDetail = ["damages", "mold", "flood", "injury", "medical", "cost", "hotel", "missed work", "couldn't use"].contains(where: lowerText.contains)
        let hasCourtPosture = ["served", "hearing", "court", "petition", "order", "filed"].contains(where: lowerText.contains)
        let hasEmploymentActor = ["boss", "manager", "hr", "supervisor", "company", "employer"].contains(where: lowerText.contains)

        switch caseType {
        case "landlord_tenant":
            var questions: [FollowUpQuestion] = []
            if jurisdiction == nil {
                questions.append(FollowUpQuestion(text: "What city and state is the property in?", priority: 10, reason: "Need jurisdiction for the next step"))
            }
            if !hasTimeline {
                questions.append(FollowUpQuestion(text: "How long has the repair problem been going on?", priority: 9, reason: "Need the repair timeline"))
            }
            if !hasWrittenNotice {
                questions.append(FollowUpQuestion(text: "Do you have emails, texts, or any written notice to the landlord about it?", priority: 8, reason: "Need notice proof"))
            }
            if !hasLease {
                questions.append(FollowUpQuestion(text: "Are you on a lease, and are you current on rent?", priority: 7, reason: "Need contract and leverage facts"))
            }
            if !hasDamageDetail {
                questions.append(FollowUpQuestion(text: "Has this caused costs, health issues, or left you without a working bathroom?", priority: 6, reason: "Need damages and pressure points"))
            }
            return questions
        case "employment":
            var questions: [FollowUpQuestion] = []
            if !hasEmploymentActor {
                questions.append(FollowUpQuestion(text: "Who made the decision or took the action against you?", priority: 10))
            }
            if !hasWrittenNotice {
                questions.append(FollowUpQuestion(text: "Do you have emails, write-ups, texts, or pay records tied to it?", priority: 9))
            }
            if jurisdiction == nil {
                questions.append(FollowUpQuestion(text: "What state did this happen in?", priority: 8))
            }
            return questions
        case "protection_order":
            var questions: [FollowUpQuestion] = []
            if !hasCourtPosture {
                questions.append(FollowUpQuestion(text: "What court is it in, and have you been served yet?", priority: 10))
            }
            if !hasWrittenNotice {
                questions.append(FollowUpQuestion(text: "Do you have the petition, hearing notice, or proof of service?", priority: 9))
            }
            return questions
        default:
            var questions: [FollowUpQuestion] = []
            if !hasTimeline {
                questions.append(FollowUpQuestion(text: "What happened first, and about when did it start?", priority: 10))
            }
            if !hasWrittenNotice {
                questions.append(FollowUpQuestion(text: "What documents, photos, texts, or emails do you already have?", priority: 9))
            }
            if jurisdiction == nil {
                questions.append(FollowUpQuestion(text: "What state is this happening in?", priority: 8))
            }
            return questions
        }
    }
}
