import Foundation

struct Case: Identifiable, Codable {
    var id: UUID
    var title: String
    var description: String
    var createdAt: Date
    var timelineEvents: [CaseTimelineEvent]
    /// Parsed AI analysis (summary, claims, damages, timeline, evidence, next steps, etc.) attached to this case.
    var analysis: CaseAnalysis?

    enum CodingKeys: String, CodingKey {
        case id, title, description, createdAt, timelineEvents, analysis
    }

    init(id: UUID = UUID(), title: String, description: String, createdAt: Date = Date(), timelineEvents: [CaseTimelineEvent] = [], analysis: CaseAnalysis? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.timelineEvents = timelineEvents
        self.analysis = analysis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        timelineEvents = try c.decodeIfPresent([CaseTimelineEvent].self, forKey: .timelineEvents) ?? []
        analysis = try c.decodeIfPresent(CaseAnalysis.self, forKey: .analysis)
    }
}
