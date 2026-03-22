import Foundation

/// A deadline identified from evidence (e.g. filing deadline, response due date). Linked by caseId.
struct LegalDeadline: Identifiable, Codable, Equatable {
    let id: UUID
    var caseId: UUID?
    var title: String
    var dueDate: Date?
    var notes: String?

    init(id: UUID = UUID(), caseId: UUID? = nil, title: String, dueDate: Date? = nil, notes: String? = nil) {
        self.id = id
        self.caseId = caseId
        self.title = title
        self.dueDate = dueDate
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey { case id, caseId, title, dueDate, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        caseId = try c.decodeIfPresent(UUID.self, forKey: .caseId)
        title = try c.decode(String.self, forKey: .title)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(caseId, forKey: .caseId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

/// Result of analyzing an evidence document: violations, timeline, damages, deadlines, missing evidence.
struct EvidenceAnalysis: Codable {
    let summary: String
    let violations: [String]
    let damages: String?
    let timelineEvents: [CaseTimelineEvent]
    let deadlines: [LegalDeadline]
    /// Evidence that may be missing or should be gathered (from "identify missing evidence").
    let missingEvidence: [String]?
}
