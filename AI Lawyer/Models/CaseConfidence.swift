import Foundation

/// Estimate of how strong a case is based on case analysis, evidence, and timeline.
struct CaseConfidence: Codable {
    let claimStrength: Int
    let evidenceStrength: String
    let settlementProbability: String
    let litigationRisk: String
}
