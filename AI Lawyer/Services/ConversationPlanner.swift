import Foundation

struct ConversationPlanner {
    func makePlan(
        payload: CaseUpdatePayload,
        userMessageCount: Int
    ) -> ConversationPlan {
        let questions = Array(payload.followUpQuestions.sorted { $0.priority > $1.priority }.prefix(1))
        let lead: String?

        if userMessageCount <= 1 {
            lead = openingLead(for: payload.caseType)
        } else if userMessageCount <= 3, let caseType = payload.caseType {
            lead = followUpLead(for: caseType)
        } else {
            lead = nil
        }

        return ConversationPlan(
            summaryLead: lead,
            nextQuestions: questions,
            shouldStayConversational: true,
            shouldOfferStrategy: userMessageCount >= 3 || payload.shouldOfferStrategy,
            shouldOfferDocuments: payload.shouldOfferDocumentChecklist && userMessageCount >= 3,
            shouldOfferTimeline: payload.shouldOfferTimelineUpdate && userMessageCount >= 2
        )
    }

    private func openingLead(for caseType: String?) -> String {
        switch caseType {
        case "landlord_tenant":
            return "This already points to a habitability and repair-notice issue."
        case "protection_order":
            return "This sounds like a protective-order matter, so court posture matters right away."
        case "employment":
            return "This already sounds like an employment claim path."
        default:
            return "I see the legal issue taking shape."
        }
    }

    private func followUpLead(for caseType: String) -> String {
        switch caseType {
        case "landlord_tenant":
            return "That helps. The notice trail and timeline matter most here."
        case "protection_order":
            return "That helps. I’m tracking service, hearing posture, and the filing record."
        default:
            return "That helps. I’m tightening the case around what’s already supported."
        }
    }
}
