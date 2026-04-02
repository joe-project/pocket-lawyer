import Testing
@testable import AI_Lawyer

struct ConversationPipelineTests {
    @Test func landlordIntakeStaysConversationalButStructured() async throws {
        let extractor = LegalSignalExtractor()
        let payload = extractor.extract(from: "My landlord still has not fixed the toilet and I have text messages and photos.")
        let plan = ConversationPlanner().makePlan(payload: payload, userMessageCount: 1)

        #expect(payload.caseType == "landlord_tenant")
        #expect(!payload.evidenceItems.isEmpty)
        #expect(!plan.nextQuestions.isEmpty)
        #expect(plan.summaryLead != nil)
    }

    @Test func protectionOrderAsksCourtAndServiceQuestions() async throws {
        let extractor = LegalSignalExtractor()
        let payload = extractor.extract(from: "I was served with a protective order and have a hearing next week.")
        let questions = payload.followUpQuestions.map(\.text).joined(separator: " ")

        #expect(payload.caseType == "protection_order")
        #expect(questions.localizedCaseInsensitiveContains("served"))
        #expect(questions.localizedCaseInsensitiveContains("court"))
    }

    @Test func directEvidenceCommandProducesEvidenceOfferSignals() async throws {
        let extractor = LegalSignalExtractor()
        let payload = extractor.extract(
            from: "Add this as evidence to the Smith case",
            attachmentNames: ["repair_photos.jpg"],
            attachmentContents: [""]
        )

        #expect(payload.shouldOfferEvidenceUpdate)
        #expect(payload.evidenceItems.contains { $0.status == .uploaded })
    }

    @Test func filingQuestionBuildsDocumentAndFilingHints() async throws {
        let extractor = LegalSignalExtractor()
        let payload = extractor.extract(from: "What forms do I need and where do I file this in Texas court?")

        #expect(payload.shouldOfferDocumentChecklist)
        #expect(payload.jurisdictionHint == "Texas")
        #expect(!payload.filingInstructions.isEmpty)
    }

    @Test func accidentCaseStillProducesFollowUpQuestions() async throws {
        let extractor = LegalSignalExtractor()
        let payload = extractor.extract(from: "I was in a car accident and the police came.")
        let plan = ConversationPlanner().makePlan(payload: payload, userMessageCount: 1)

        #expect(payload.caseType == "injury_accident")
        #expect(!plan.nextQuestions.isEmpty)
    }
}
