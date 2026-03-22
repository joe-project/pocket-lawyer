import Foundation

/// Strategic legal analysis of a case that evolves as new information is added.
struct LitigationStrategy: Codable {
    var legalTheories: [String]
    var strengths: [String]
    var weaknesses: [String]
    var evidenceGaps: [String]
    var opposingArguments: [String]
    var settlementRange: String?
    var litigationPlan: [String]
}
