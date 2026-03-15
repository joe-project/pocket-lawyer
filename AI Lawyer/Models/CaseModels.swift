import Foundation

enum CaseCategory: String, CaseIterable, Identifiable, Codable {
    case potentialWinnings = "Potential Winnings"
    case inProgress = "Cases In Progress"
    case closed = "Cases Won"

    var id: String { rawValue }
}

enum CaseSubfolder: String, CaseIterable, Identifiable, Codable {
    case filedDocuments = "Filed Documents"
    case response = "Response"
    case evidence = "Evidence"
    case documents = "Documents"
    case recordings = "Recordings"
    case history = "History"
    case timeline = "Timeline"

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
    /// For AI-generated documents, inline content so user can view/download. For images, nil and data stored on disk at relativePath.
    var content: String?

    init(id: UUID = UUID(),
         name: String,
         type: CaseFileType,
         relativePath: String,
         createdAt: Date = Date(),
         content: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.content = content
    }
}

struct CaseFolder: Identifiable, Codable {
    var id: UUID
    var title: String
    var category: CaseCategory
    var subfolders: [CaseSubfolder: [CaseFile]]
    /// Custom display names for folders; default is CaseSubfolder.rawValue.
    var customFolderNames: [CaseSubfolder: String]

    init(id: UUID = UUID(),
         title: String,
         category: CaseCategory,
         subfolders: [CaseSubfolder: [CaseFile]] = [:],
         customFolderNames: [CaseSubfolder: String] = [:]) {
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
    }

    func displayName(for subfolder: CaseSubfolder) -> String {
        customFolderNames[subfolder] ?? subfolder.rawValue
    }
}
