import Foundation

enum CaseCategory: String, CaseIterable, Identifiable, Codable {
    case potentialWinnings = "Potential Winnings"
    case inProgress = "Cases In Progress"
    case closed = "Cases Won"
    case mockCases = "Mock Cases"

    var id: String { rawValue }
}

enum CaseSubfolder: String, CaseIterable, Identifiable, Codable {
    case evidence = "Evidence"
    case documents = "Documents"
    case response = "Responses"
    case recordings = "Recordings"
    case timeline = "Timeline"
    case history = "History"
    case filedDocuments = "Filed Documents"

    var id: String { rawValue }
}

/// Case-centric workspace navigation (replaces folder grouping in the sidebar).
enum CaseWorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case timeline = "Timeline"
    case chat = "Chat"
    case recordings = "Recordings"
    case evidence = "Evidence"
    case documents = "Documents"
    case emails = "Emails"
    case deadlines = "Deadlines"
    case tasks = "Tasks"
    case history = "History"

    var id: String { rawValue }

    /// For sections that map to a document list, the CaseSubfolder to use.
    var documentSubfolder: CaseSubfolder? {
        switch self {
        case .evidence: return .evidence
        case .documents: return .documents
        case .history: return .history
        default: return nil
        }
    }
}

/// Subfolders under Recordings (Voice Stories, Witness Statements, etc.).
enum RecordingSubfolder: String, CaseIterable, Identifiable, Codable {
    case voiceStories = "Voice Stories"
    case witnessStatements = "Witness Statements"
    case notes = "Notes"
    case depositions = "Depositions"

    var id: String { rawValue }
}

enum TimelineSubitem: String, CaseIterable, Identifiable {
    case timelineView = "Timeline view"
    case deadlines = "Deadlines"
    case tasks = "Tasks"
    var id: String { rawValue }
}

enum TimelineEventKind: String, Codable {
    case task
    case filing
    case response
}

enum ResponseTag: String, Codable, CaseIterable, Identifiable, Equatable {
    case note
    case draft
    case strategy
    case evidence

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

struct TimelineEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: TimelineEventKind
    var title: String
    var summary: String?
    var createdAt: Date
    var documentId: UUID?
    var subfolder: CaseSubfolder?

    init(id: UUID = UUID(),
         kind: TimelineEventKind,
         title: String,
         summary: String? = nil,
         createdAt: Date = Date(),
         documentId: UUID? = nil,
         subfolder: CaseSubfolder? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.documentId = documentId
        self.subfolder = subfolder
    }
}

enum CaseFileType: String, Codable {
    case pdf
    case docx
    case image
    case audio
    case note
    case other
}

struct CaseFile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var type: CaseFileType
    var relativePath: String
    var createdAt: Date
    /// Case this file belongs to. Optional for backward compatibility with existing saved data.
    var caseId: UUID?
    /// When in Recordings, which subfolder (Voice Stories, Witness Statements, etc.). Nil for legacy or non-recording files.
    var recordingSubfolder: RecordingSubfolder?
    /// For AI-generated documents, inline content so user can view/download. For images, nil and data stored on disk at relativePath.
    var content: String?
    /// Length in seconds (e.g. for audio recordings). Optional for backward compatibility.
    var durationSeconds: Int?

    /// AI response classification for file-first loops (e.g. note/draft/strategy/evidence).
    var responseTag: ResponseTag?
    /// Stable grouping key used for version history rollbacks.
    var versionGroupId: String?
    /// Version number within the versionGroupId (v1, v2, ...).
    var versionNumber: Int?

    init(id: UUID = UUID(),
         name: String,
         type: CaseFileType,
         relativePath: String,
         createdAt: Date = Date(),
         caseId: UUID? = nil,
         recordingSubfolder: RecordingSubfolder? = nil,
         content: String? = nil,
         durationSeconds: Int? = nil,
         responseTag: ResponseTag? = nil,
         versionGroupId: String? = nil,
         versionNumber: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.caseId = caseId
        self.recordingSubfolder = recordingSubfolder
        self.content = content
        self.durationSeconds = durationSeconds

        self.responseTag = responseTag
        self.versionGroupId = versionGroupId
        self.versionNumber = versionNumber
    }
}

struct CaseFolder: Identifiable, Codable {
    var id: UUID
    var title: String
    var category: CaseCategory
    var subfolders: [CaseSubfolder: [CaseFile]]
    /// Custom display names for folders; default is CaseSubfolder.rawValue.
    var customFolderNames: [CaseSubfolder: String]
    /// Hidden built-in subfolders. Hiding preserves files and linkage, but removes the node from the sidebar tree.
    var hiddenSubfolders: [CaseSubfolder]
    /// Email drafts generated for this case (stored locally; never sent automatically).
    var emailDrafts: [EmailDraft]
    /// Deadlines identified from evidence or case (e.g. response due, filing deadline).
    var deadlines: [LegalDeadline]
    /// Assigned by the court after filing; user-entered when known.
    var courtCaseNumber: String?

    init(id: UUID = UUID(),
         title: String,
         category: CaseCategory,
         subfolders: [CaseSubfolder: [CaseFile]] = [:],
         customFolderNames: [CaseSubfolder: String] = [:],
         hiddenSubfolders: [CaseSubfolder] = [.response, .recordings, .history, .filedDocuments],
         emailDrafts: [EmailDraft] = [],
         deadlines: [LegalDeadline] = [],
         courtCaseNumber: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        var initial: [CaseSubfolder: [CaseFile]] = [:]
        CaseSubfolder.allCases.forEach { initial[$0] = [] }
        subfolders.forEach { key, value in
            initial[key] = value
        }
        self.subfolders = initial
        self.customFolderNames = customFolderNames
        self.hiddenSubfolders = hiddenSubfolders
        self.emailDrafts = emailDrafts
        self.deadlines = deadlines
        self.courtCaseNumber = courtCaseNumber
    }

    enum CodingKeys: String, CodingKey {
        case id, title, category, subfolders, customFolderNames, hiddenSubfolders, emailDrafts, deadlines, courtCaseNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(CaseCategory.self, forKey: .category)
        subfolders = try c.decode([CaseSubfolder: [CaseFile]].self, forKey: .subfolders)
        customFolderNames = try c.decode([CaseSubfolder: String].self, forKey: .customFolderNames)
        hiddenSubfolders = try c.decodeIfPresent([CaseSubfolder].self, forKey: .hiddenSubfolders) ?? [.response, .recordings, .history, .filedDocuments]
        emailDrafts = try c.decodeIfPresent([EmailDraft].self, forKey: .emailDrafts) ?? []
        deadlines = try c.decodeIfPresent([LegalDeadline].self, forKey: .deadlines) ?? []
        courtCaseNumber = try c.decodeIfPresent(String.self, forKey: .courtCaseNumber)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
        try c.encode(subfolders, forKey: .subfolders)
        try c.encode(customFolderNames, forKey: .customFolderNames)
        try c.encode(hiddenSubfolders, forKey: .hiddenSubfolders)
        try c.encode(emailDrafts, forKey: .emailDrafts)
        try c.encode(deadlines, forKey: .deadlines)
        try c.encodeIfPresent(courtCaseNumber, forKey: .courtCaseNumber)
    }

    func displayName(for subfolder: CaseSubfolder) -> String {
        customFolderNames[subfolder] ?? subfolder.rawValue
    }
}
