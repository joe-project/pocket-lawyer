import Foundation

/// A timeline event (e.g. from case analysis or evidence). Linked by caseId.
struct CaseTimelineEvent: Identifiable, Codable {
    let id: UUID
    var caseId: UUID?
    let date: Date?
    let description: String

    init(id: UUID = UUID(), caseId: UUID? = nil, date: Date?, description: String) {
        self.id = id
        self.caseId = caseId
        self.date = date
        self.description = description
    }

    enum CodingKeys: String, CodingKey { case id, caseId, date, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        caseId = try c.decodeIfPresent(UUID.self, forKey: .caseId)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        description = try c.decode(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(caseId, forKey: .caseId)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encode(description, forKey: .description)
    }
}
