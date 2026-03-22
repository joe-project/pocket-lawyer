import Foundation

struct CaseActivity: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let timestamp: Date
    let type: String
}
