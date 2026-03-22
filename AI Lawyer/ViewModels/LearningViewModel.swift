import Foundation
import Combine

@MainActor
final class LearningViewModel: ObservableObject {
    @Published var topics: [LearningCategory: [LearningTopic]] = [:]

    init() {
        seed()
    }

    private func seed() {
        func makeSummary(for category: LearningCategory) -> String {
            switch category {
            case .realEstateLaw:
                return "Covers ownership, transfer, and use of real property."
            case .criminalLaw:
                return "Overview of criminal offenses, defenses, and the justice process."
            case .insuranceLaw:
                return "Explains insurance policies, claims, and coverage disputes."
            case .trustLaw:
                return "Explains how trusts are created and managed for beneficiaries."
            case .lawsuits:
                return "Outlines the life cycle of a civil lawsuit."
            case .creditRepair:
                return "Describes how credit reports and disputes work."
            case .contracts:
                return "Introduces contract formation and enforcement."
            case .civilProcedure:
                return "Covers court rules for civil cases."
            case .patents:
                return "Summarizes patent protection for inventions."
            case .businessLaw:
                return "Reviews business structures and compliance."
            }
        }

        var dict: [LearningCategory: [LearningTopic]] = [:]
        for category in LearningCategory.allCases {
            let topic = LearningTopic(title: category.rawValue,
                                      summary: makeSummary(for: category))
            dict[category] = [topic]
        }
        topics = dict
    }
}
