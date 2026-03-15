import Foundation
import Combine

@MainActor
final class CaseTreeViewModel: ObservableObject {
    @Published var cases: [CaseFolder] = []
    @Published var selectedCase: CaseFolder?
    @Published var selectedSubfolder: CaseSubfolder = .evidence
    @Published var timelineEvents: [UUID: [TimelineEvent]] = [:]

    private let storage = LocalCaseStorage.shared

    init() {
        let (loadedCases, loadedTimeline) = storage.load()
        if loadedCases.isEmpty {
            seedSampleData()
            seedSampleTimeline()
        } else {
            cases = loadedCases
            timelineEvents = loadedTimeline
            selectedCase = cases.first
        }
        save()
    }

    private func save() {
        storage.save(cases: cases, timelineEvents: timelineEvents)
    }

    private func seedSampleData() {
        cases = [
            CaseFolder(title: "Case #1", category: .inProgress),
            CaseFolder(title: "Case 2 vs. [Defendant]", category: .closed),
            CaseFolder(title: "Case 3 vs. [Defendant]", category: .inProgress)
        ]
        selectedCase = cases.first
    }

    private func seedSampleTimeline() {
        guard let first = cases.first else { return }
        timelineEvents[first.id] = [
            TimelineEvent(kind: .task, title: "Initial intake", summary: "Client information gathered", createdAt: Date().addingTimeInterval(-86400 * 2)),
            TimelineEvent(kind: .filing, title: "Complaint filed", summary: "Filed with court", createdAt: Date().addingTimeInterval(-86400)),
            TimelineEvent(kind: .response, title: "Draft response", summary: "AI-generated draft", createdAt: Date())
        ]
    }

    func events(for caseId: UUID) -> [TimelineEvent] {
        (timelineEvents[caseId] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func addTimelineEvent(_ event: TimelineEvent, caseId: UUID) {
        var list = timelineEvents[caseId] ?? []
        list.append(event)
        timelineEvents[caseId] = list
        save()
    }

    func revertTimeline(to eventId: UUID, caseId: UUID) {
        guard var list = timelineEvents[caseId],
              let index = list.firstIndex(where: { $0.id == eventId }) else { return }
        timelineEvents[caseId] = Array(list.prefix(through: index))
        save()
    }

    /// Display name for a folder in a case (custom or default).
    func folderDisplayName(caseId: UUID, subfolder: CaseSubfolder) -> String {
        cases.first(where: { $0.id == caseId })?.displayName(for: subfolder) ?? subfolder.rawValue
    }

    /// Set custom display name for a folder in a case.
    func setFolderDisplayName(caseId: UUID, subfolder: CaseSubfolder, name: String) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cases[idx].customFolderNames.removeValue(forKey: subfolder)
        } else {
            cases[idx].customFolderNames[subfolder] = trimmed
        }
        save()
    }

    /// Add a document with optional on-disk content (all stored on device).
    func addGeneratedDocument(caseId: UUID, subfolder: CaseSubfolder, name: String, content: String) -> (CaseFile, TimelineEvent)? {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return nil }
        let docId = UUID()
        let relPath = "CaseFiles/\(caseId.uuidString)/\(subfolder.rawValue.replacingOccurrences(of: " ", with: "_"))/\(docId.uuidString).docx"
        let file = CaseFile(
            id: docId,
            name: name,
            type: .docx,
            relativePath: relPath,
            content: content
        )
        storage.writeFileContent(caseId: caseId, subfolder: subfolder, fileId: docId, type: .docx, content: content)
        let event = TimelineEvent(kind: .response, title: name, summary: "AI-generated document", documentId: docId, subfolder: subfolder)
        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(file)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        addTimelineEvent(event, caseId: caseId)
        return (file, event)
    }

    /// Add an image file (stored on device).
    func addImage(caseId: UUID, subfolder: CaseSubfolder, name: String, imageData: Data) -> CaseFile? {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return nil }
        let fileId = UUID()
        let relPath = "CaseFiles/\(caseId.uuidString)/\(subfolder.rawValue.replacingOccurrences(of: " ", with: "_"))/\(fileId.uuidString).jpg"
        storage.writeImage(caseId: caseId, subfolder: subfolder, fileId: fileId, data: imageData)
        let file = CaseFile(id: fileId, name: name, type: .image, relativePath: relPath)
        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(file)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        save()
        return file
    }

    /// Add any file (e.g. user-created document). Content is stored on device.
    func addFile(caseId: UUID, subfolder: CaseSubfolder, file: CaseFile, content: String?) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        let contentToWrite = content ?? ""
        storage.writeFileContent(caseId: caseId, subfolder: subfolder, fileId: file.id, type: file.type, content: contentToWrite)
        let subfolderDir = subfolder.rawValue.replacingOccurrences(of: " ", with: "_")
        let ext = file.type == .docx ? "docx" : "txt"
        var fileWithPath = file
        fileWithPath.relativePath = "CaseFiles/\(caseId.uuidString)/\(subfolderDir)/\(file.id.uuidString).\(ext)"
        fileWithPath.content = contentToWrite.isEmpty ? nil : contentToWrite
        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(fileWithPath)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        save()
    }

    /// Update file name or content (stored on device).
    func updateFile(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID, newName: String?, newContent: String?) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }),
              var files = cases[idx].subfolders[subfolder],
              let fileIdx = files.firstIndex(where: { $0.id == fileId }) else { return }
        if let name = newName, !name.isEmpty { files[fileIdx].name = name }
        if let content = newContent {
            files[fileIdx].content = content
            storage.writeFileContent(caseId: caseId, subfolder: subfolder, fileId: fileId, type: files[fileIdx].type, content: content)
        }
        cases[idx].subfolders[subfolder] = files
        save()
    }

    func files(for caseId: UUID, subfolder: CaseSubfolder) -> [CaseFile] {
        cases.first(where: { $0.id == caseId })?.subfolders[subfolder] ?? []
    }

    /// Full URL for download/share (on device).
    func fileURL(for file: CaseFile) -> URL {
        storage.fullURL(relativePath: file.relativePath)
    }

    func fileExistsOnDisk(_ file: CaseFile) -> Bool {
        storage.fileExists(relativePath: file.relativePath)
    }
}
