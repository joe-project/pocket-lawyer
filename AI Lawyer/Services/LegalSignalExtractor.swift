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
        let requestedActions = detectRequestedActions(in: lower)
        let timelineEvents = detectTimelineEvents(in: trimmed)
        let facts = detectFacts(in: trimmed, caseType: caseType, jurisdiction: jurisdiction, requestedActions: requestedActions, evidenceItems: evidenceItems, timelineEvents: timelineEvents)
        let followUpQuestions = defaultFollowUpQuestions(for: caseType, lowerText: lower, jurisdiction: jurisdiction)

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
            followUpQuestions: followUpQuestions,
            requestedActions: requestedActions,
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

    private func detectEvidence(in lower: String, attachmentNames: [String], messageId: UUID?) -> [EvidenceItem] {
        var items: [EvidenceItem] = []
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
            items.append(EvidenceItem(title: category, category: category, status: .need, linkedMessageId: messageId, isTentative: true))
        }

        for name in attachmentNames {
            items.append(EvidenceItem(title: name, category: "Uploaded", status: .uploaded, linkedMessageId: messageId))
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

    private func detectRequestedActions(in lower: String) -> [String] {
        ["add this to the case", "add this as evidence", "put this under timeline", "attach this", "what documents do i need", "where do i file this", "what should i print", "what do i serve first"]
            .filter { lower.contains($0) }
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
        evidenceItems: [EvidenceItem],
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
        switch caseType {
        case "landlord_tenant":
            return [
                FollowUpQuestion(text: lowerText.contains("landlord") ? "What happened first, and when did it start?" : "What happened first?", priority: 10, reason: "Need the opening timeline"),
                FollowUpQuestion(text: "Do you have the lease and written notice to the landlord?", priority: 9, reason: "Need the strongest supporting documents"),
                FollowUpQuestion(text: jurisdiction == nil ? "What city and state is the property in?" : "Has the landlord responded or fixed anything yet?", priority: 8, reason: "Need venue or response facts")
            ]
        case "employment":
            return [
                FollowUpQuestion(text: "Who made the decision or took the action against you?", priority: 10),
                FollowUpQuestion(text: "Do you have emails, write-ups, or pay records?", priority: 9)
            ]
        case "protection_order":
            return [
                FollowUpQuestion(text: "What court is it in, and were you served yet?", priority: 10),
                FollowUpQuestion(text: "Do you have the petition, hearing date, and proof of service?", priority: 9)
            ]
        default:
            return [
                FollowUpQuestion(text: "Start with the moment it began. What happened first?", priority: 10),
                FollowUpQuestion(text: "What documents, photos, or messages do you already have?", priority: 9)
            ]
        }
    }
}
