import Foundation

/// Saves and loads all case data, documents, and images on the device only (no cloud).
final class LocalCaseStorage {
    static let shared = LocalCaseStorage()

    private let fileManager = FileManager.default
    private let casesFileName = "caseData.json"

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var caseDataURL: URL {
        documentsURL.appendingPathComponent(casesFileName)
    }

    private var caseFilesBaseURL: URL {
        documentsURL.appendingPathComponent("CaseFiles", isDirectory: true)
    }

    private init() {}

    // MARK: - Cases & timeline (JSON)

    struct PersistedState: Codable {
        let cases: [CaseFolder]
        let timelineEvents: [String: [TimelineEvent]] // UUID string keys
    }

    func load() -> (cases: [CaseFolder], timelineEvents: [UUID: [TimelineEvent]]) {
        guard fileManager.fileExists(atPath: caseDataURL.path),
              let data = try? Data(contentsOf: caseDataURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return ([], [:])
        }
        var timeline: [UUID: [TimelineEvent]] = [:]
        for (key, events) in state.timelineEvents {
            if let uuid = UUID(uuidString: key) {
                timeline[uuid] = events
            }
        }
        return (state.cases, timeline)
    }

    func save(cases: [CaseFolder], timelineEvents: [UUID: [TimelineEvent]]) {
        let timelineDict = Dictionary(uniqueKeysWithValues: timelineEvents.map { ($0.key.uuidString, $0.value) })
        let state = PersistedState(cases: cases, timelineEvents: timelineDict)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: caseDataURL)
    }

    // MARK: - File contents (on disk)

    func fileURL(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID, type: CaseFileType) -> URL {
        let dir = caseFilesBaseURL
            .appendingPathComponent(caseId.uuidString, isDirectory: true)
            .appendingPathComponent(subfolder.rawValue.replacingOccurrences(of: " ", with: "_"), isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext: String
        switch type {
        case .image: ext = "jpg"
        case .pdf: ext = "pdf"
        case .docx: ext = "docx"
        case .audio: ext = "m4a"
        default: ext = "txt"
        }
        return dir.appendingPathComponent("\(fileId.uuidString).\(ext)")
    }

    /// Write text content to disk. relativePath stored in CaseFile should match this.
    func writeFileContent(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID, type: CaseFileType, content: String) {
        let url = fileURL(caseId: caseId, subfolder: subfolder, fileId: fileId, type: type)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Write image data to disk.
    func writeImage(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID, data: Data) {
        let url = fileURL(caseId: caseId, subfolder: subfolder, fileId: fileId, type: .image)
        try? data.write(to: url)
    }

    /// Read text content from disk (for files that store content on disk instead of in-memory).
    func readFileContent(at relativePath: String) -> String? {
        let url = documentsURL.appendingPathComponent(relativePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Full URL for a file (e.g. for sharing / export).
    func fullURL(relativePath: String) -> URL {
        documentsURL.appendingPathComponent(relativePath)
    }

    /// Check if file exists on disk (for images / stored docs).
    func fileExists(relativePath: String) -> Bool {
        fileManager.fileExists(atPath: documentsURL.appendingPathComponent(relativePath).path)
    }
}
