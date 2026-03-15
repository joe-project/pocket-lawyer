import Foundation

struct Case: Identifiable, Codable {
    var id: UUID
    var title: String
    var description: String
    var createdAt: Date
}
