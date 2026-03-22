import Foundation

struct Message: Identifiable, Codable {
    var id: UUID
    var caseId: UUID?
    /// File that this message is tied to in the Legal OS file-first loop.
    var fileId: UUID?
    var role: String
    var content: String
    var timestamp: Date
    /// Present for AI assistant messages saved from the response loop.
    var responseTag: ResponseTag?
    /// File names of attachments (e.g. "lease.pdf", "photo.jpg"). Shown in UI and included in AI context.
    var attachmentNames: [String]
    /// Resolved text content for each attachment (same order as attachmentNames). Used when sending to AI; empty string for non-text (e.g. image).
    var attachmentContents: [String]

    init(
        id: UUID = UUID(),
        caseId: UUID? = nil,
        fileId: UUID? = nil,
        role: String,
        content: String,
        timestamp: Date = Date(),
        responseTag: ResponseTag? = nil,
        attachmentNames: [String] = [],
        attachmentContents: [String] = []
    ) {
        self.id = id
        self.caseId = caseId
        self.fileId = fileId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.responseTag = responseTag
        self.attachmentNames = attachmentNames
        self.attachmentContents = attachmentContents
    }

    enum CodingKeys: String, CodingKey {
        case id, caseId, fileId, role, content, timestamp, responseTag, attachmentNames, attachmentContents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        caseId = try c.decodeIfPresent(UUID.self, forKey: .caseId)
        fileId = try c.decodeIfPresent(UUID.self, forKey: .fileId)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        responseTag = try c.decodeIfPresent(ResponseTag.self, forKey: .responseTag)
        attachmentNames = try c.decodeIfPresent([String].self, forKey: .attachmentNames) ?? []
        attachmentContents = try c.decodeIfPresent([String].self, forKey: .attachmentContents) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(caseId, forKey: .caseId)
        try c.encodeIfPresent(fileId, forKey: .fileId)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        if let tag = responseTag { try c.encode(tag, forKey: .responseTag) }
        if !attachmentNames.isEmpty { try c.encode(attachmentNames, forKey: .attachmentNames) }
        if !attachmentContents.isEmpty { try c.encode(attachmentContents, forKey: .attachmentContents) }
    }
}
