import Foundation

/// Email draft for the case. Linked by caseId.
struct EmailDraft: Identifiable, Codable {
    let id: UUID
    var caseId: UUID?
    let subject: String
    let body: String
    let suggestedRecipient: String?
    let createdAt: Date

    init(id: UUID = UUID(), caseId: UUID? = nil, subject: String, body: String, suggestedRecipient: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.caseId = caseId
        self.subject = subject
        self.body = body
        self.suggestedRecipient = suggestedRecipient
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, caseId, subject, body, suggestedRecipient, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        caseId = try c.decodeIfPresent(UUID.self, forKey: .caseId)
        subject = try c.decode(String.self, forKey: .subject)
        body = try c.decode(String.self, forKey: .body)
        suggestedRecipient = try c.decodeIfPresent(String.self, forKey: .suggestedRecipient)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(caseId, forKey: .caseId)
        try c.encode(subject, forKey: .subject)
        try c.encode(body, forKey: .body)
        try c.encodeIfPresent(suggestedRecipient, forKey: .suggestedRecipient)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
