import Foundation

struct ConversationPlanner {
    func makePlan(
        payload: CaseUpdatePayload,
        userMessageCount: Int
    ) -> ConversationPlan {
        let questions = Array(payload.followUpQuestions.sorted { $0.priority > $1.priority }.prefix(3))
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
            return "Got it. Let’s pin down the facts first so we can build this cleanly."
        case "protection_order":
            return "Okay. Before strategy, I want to make sure we know the court posture and service status."
        case "employment":
            return "Understood. Let’s get the core facts straight before we decide the path."
        default:
            return "Got it. Let’s build this step by step."
        }
    }

    private func followUpLead(for caseType: String) -> String {
        switch caseType {
        case "landlord_tenant":
            return "That helps. I’m sorting the timeline and evidence in the background."
        case "protection_order":
            return "That helps. I’m tracking the filing posture and what documents we still need."
        default:
            return "That helps. I’m organizing the case around what you’ve told me."
        }
    }
}
