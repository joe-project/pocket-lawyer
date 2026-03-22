import Foundation

struct CaseAnalysis: Codable {
    var summary: String
    var claims: [String]
    var estimatedDamages: String
    var evidenceNeeded: [String]
    var timeline: [CaseTimelineEvent]
    var nextSteps: [String]
    var documents: [String]
    var filingLocations: [String]
}
