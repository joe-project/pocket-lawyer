import Foundation

struct Message: Identifiable, Codable {
    var id: UUID
    var caseId: UUID?
    var role: String
    var content: String
    var timestamp: Date
}
