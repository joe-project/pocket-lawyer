import Foundation
import Combine

@MainActor
final class CaseTreeViewModel: ObservableObject {
    static let startHereTitle = "Start Here"
    static let exampleCaseTitle = "Order of Protection – Example"

    @Published var cases: [CaseFolder] = []
    @Published var selectedCase: CaseFolder?
    /// Workspace tab (Overview, Timeline, Chat, etc.). Replaces folder grouping.
    @Published var selectedWorkspaceSection: CaseWorkspaceSection = .chat
    /// Kept for DocumentListView; set in sync when selecting Evidence/Documents/History.
    @Published var selectedSubfolder: CaseSubfolder = .evidence
    /// Active file selected from the sidebar file tree (used for preview).
    @Published var selectedFileId: UUID? = nil
    @Published var timelineEvents: [UUID: [TimelineEvent]] = [:]

    private let storage = LocalCaseStorage.shared

    init() {
        let (loadedCases, loadedTimeline) = storage.load()
        if loadedCases.isEmpty {
            seedStarterData()
        } else {
            cases = ordered(migrateLoadedCases(loadedCases))
            timelineEvents = loadedTimeline
            ensurePinnedTimelineEntries()
            selectedCase = startHereFolder ?? cases.first
        }
        selectedWorkspaceSection = .chat
        selectedSubfolder = .evidence
        selectedFileId = nil
        save()
    }

    private func save() {
        storage.save(cases: cases, timelineEvents: timelineEvents)
    }

    private func seedStarterData() {
        let startHere = makeStartHereFolder(id: UUID())
        let example = makeExampleCase(id: UUID())
        cases = ordered([startHere, example])
        timelineEvents[startHere.id] = []
        timelineEvents[example.id] = exampleTimelineEvents()
        selectedCase = startHere
    }

    private func migrateLoadedCases(_ loadedCases: [CaseFolder]) -> [CaseFolder] {
        let oldDemoTitles: Set<String> = [
            "General Law Questions",
            "Jones vs. Smith (Example Case)",
            "Trust Law",
            "Family Trust Documents",
            "Smith vs Jones",
            "Smith vs Johson",
            "Smith vs. Johnson",
            "Brown vs State",
            "Davis vs Miller",
            "Marriage & Family",
            "Credit",
            "Civil Law",
            "Real Estate Law",
            "Dufff Vs. Banks"
        ]

        var updated = loadedCases
            .filter { !oldDemoTitles.contains($0.title) }
            .map(normalizedCaseFolder(_:))

        if !updated.contains(where: { $0.isBuilderTemplate || $0.title == Self.startHereTitle }) {
            updated.insert(makeStartHereFolder(id: UUID()), at: 0)
        }

        if let exampleIndex = updated.firstIndex(where: { $0.title == "Example Case" }) {
            let existingId = updated[exampleIndex].id
            updated[exampleIndex] = makeExampleCase(id: existingId)
        } else if !updated.contains(where: { $0.title == Self.exampleCaseTitle }) {
            updated.append(makeExampleCase(id: UUID()))
        }

        return ordered(updated)
    }

    private func makeStartHereFolder(id: UUID) -> CaseFolder {
        var folder = CaseFolder(
            id: id,
            title: Self.startHereTitle,
            category: .inProgress,
            isBuilderTemplate: true,
            sidebarSortIndex: 0
        )
        folder.hiddenSubfolders = CaseSubfolder.allCases.filter { $0 != .history }
        folder.customFolderNames[.history] = "Builder Notes"
        return folder
    }

    private func makeExampleCase(id: UUID) -> CaseFolder {
        var folder = CaseFolder(
            id: id,
            title: Self.exampleCaseTitle,
            category: .inProgress,
            subfolders: exampleSubfolders(caseId: id),
            hiddenSubfolders: [.recordings, .history, .filedDocuments],
            isReadOnly: true,
            sidebarSortIndex: 1
        )
        folder.customFolderNames[.strategy] = "Strategy"
        folder.customFolderNames[.coaching] = "Coaching"
        folder.customFolderNames[.decisionTreePathways] = "Decision Tree Pathways"
        folder.customFolderNames[.sayDontSay] = "Say / Don't Say"
        return folder
    }

    private func normalizedCaseFolder(_ folder: CaseFolder) -> CaseFolder {
        var normalized = folder
        if normalized.title == Self.startHereTitle {
            normalized.isBuilderTemplate = true
            normalized.isReadOnly = false
            normalized.sidebarSortIndex = 0
            normalized.hiddenSubfolders = CaseSubfolder.allCases.filter { $0 != .history }
            normalized.customFolderNames[.history] = normalized.customFolderNames[.history] ?? "Builder Notes"
            return normalized
        }
        if normalized.title == Self.exampleCaseTitle || normalized.title == "Example Case" {
            return makeExampleCase(id: normalized.id)
        }
        let hiddenDefaults: [CaseSubfolder] = [.recordings, .history, .filedDocuments]
        for subfolder in hiddenDefaults where !normalized.hiddenSubfolders.contains(subfolder) {
            normalized.hiddenSubfolders.append(subfolder)
        }
        normalized.hiddenSubfolders.removeAll(where: { $0 == .response })
        normalized.customFolderNames[.strategy] = normalized.customFolderNames[.strategy] ?? "Strategy"
        normalized.customFolderNames[.coaching] = normalized.customFolderNames[.coaching] ?? "Coaching"
        normalized.customFolderNames[.decisionTreePathways] = normalized.customFolderNames[.decisionTreePathways] ?? "Decision Tree Pathways"
        normalized.customFolderNames[.sayDontSay] = normalized.customFolderNames[.sayDontSay] ?? "Say / Don't Say"
        normalized.isReadOnly = false
        normalized.isBuilderTemplate = false
        return normalized
    }

    var orderedCases: [CaseFolder] {
        ordered(cases)
    }

    var startHereFolder: CaseFolder? {
        cases.first { $0.isBuilderTemplate || $0.title == Self.startHereTitle }
    }

    func isStartHereCase(_ caseId: UUID?) -> Bool {
        guard let caseId else { return true }
        return cases.first(where: { $0.id == caseId }).map { $0.isBuilderTemplate || $0.title == Self.startHereTitle } ?? true
    }

    func isReadOnlyCase(_ caseId: UUID) -> Bool {
        cases.first(where: { $0.id == caseId })?.isReadOnly == true
    }

    private func canMutateCase(_ caseId: UUID) -> Bool {
        !isReadOnlyCase(caseId)
    }

    private func ordered(_ folders: [CaseFolder]) -> [CaseFolder] {
        folders.sorted { lhs, rhs in
            let left = lhs.sidebarSortIndex ?? Int.max
            let right = rhs.sidebarSortIndex ?? Int.max
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func ensurePinnedTimelineEntries() {
        if let start = startHereFolder {
            timelineEvents[start.id] = timelineEvents[start.id] ?? []
        }
        if let example = cases.first(where: { $0.title == Self.exampleCaseTitle }) {
            timelineEvents[example.id] = exampleTimelineEvents()
        }
    }

    private func exampleSubfolders(caseId: UUID) -> [CaseSubfolder: [CaseFile]] {
        [
            .history: [
                exampleNote("Chat Transcript", caseId: caseId, content: """
                User: “My ex has been showing up at my house and texting threats. I’m scared and don’t know what to do.”
                Assistant: “Understood. I can help you file a protection order and organize your evidence. Were there any direct threats of harm and do you have dates/screenshots?”
                User: “Yes—texts from last week and he showed up twice uninvited.”
                Assistant: “Got it. I’ll build your case file: timeline, evidence log, filing steps, and what to say in court.”
                """)
            ],
            .evidence: [
                exampleNote("Incident Log", caseId: caseId, content: """
                - 2026-03-01: Uninvited visit; refused to leave for 20 minutes.
                - 2026-03-03: Threatening text: “you’ll regret this.”
                - 2026-03-05: 12 missed calls within 1 hour.
                - 2026-03-07: Second uninvited visit; neighbor witnessed.
                - 2026-03-08: Explicit threat: “I’m coming over tonight.”

                Evidence to attach:
                - screenshots
                - call logs
                - doorbell/video footage
                - neighbour statement
                - police report if available
                """)
            ],
            .documents: [
                exampleNote("Protection Order Filing Checklist", caseId: caseId, content: """
                1. Complete protection order petition.
                2. Add dates, locations, and threat details.
                3. Attach screenshots and call logs.
                4. Add witness names and contact information.
                5. Request temporary/emergency order if danger is immediate.
                6. File with county clerk or domestic violence protection order office.
                7. Prepare for hearing.
                """),
                exampleNote("Emergency vs Standard Order", caseId: caseId, content: """
                Emergency / Ex Parte Order:
                Used when immediate danger exists. Judge may issue temporary protection before respondent appears.

                Standard Protection Order:
                Issued after hearing. Respondent has chance to appear. Usually lasts longer.
                """)
            ],
            .response: [
                exampleNote("If Respondent Denies Allegations", caseId: caseId, content: """
                Stay factual.

                Say:
                “The denial does not match the documented texts, call logs, and witness account.”

                Then point to:
                - exact dates
                - screenshots
                - call history
                - witness statement

                Ask the court to rely on documented evidence.
                """)
            ],
            .strategy: [
                exampleNote("Initial Strategy", caseId: caseId, content: """
                Recommended path:
                File emergency protection order immediately.

                Why:
                There is a pattern of escalation:
                - repeated unwanted contact
                - threats
                - uninvited visits
                - possible witness

                Strengths:
                - dated messages
                - call records
                - witness
                - repeated behaviour

                Weaknesses:
                - need screenshots preserved
                - need proof of physical visits
                - need witness statement if possible

                Next action:
                Prepare petition, attach evidence, request emergency order.
                """)
            ],
            .coaching: [
                exampleNote("Courtroom Coaching", caseId: caseId, content: """
                Tell the judge:
                “I am afraid for my safety because of repeated incidents on these dates.”

                Focus on:
                - what happened
                - when it happened
                - why it made you afraid
                - what evidence supports it

                Do not ramble.
                Do not argue.
                Do not speculate.
                Do not exaggerate.
                """)
            ],
            .decisionTreePathways: [
                exampleNote("Pathways Overview", caseId: caseId, content: """
                PATH 1 — File Immediately
                title: File Immediately
                description: File for emergency protection based on recent threats and escalating unwanted contact.
                recommended_when: Use when threats are recent or escalating.
                risk_level: low delay risk, high urgency
                next_steps:
                - complete petition
                - attach evidence
                - file ex parte today

                PATH 2 — Gather More Evidence First
                title: Gather More Evidence First
                description: Strengthen documentation before filing if current proof is incomplete.
                recommended_when: Use when documentation is weak.
                risk_level: delay could increase danger
                next_steps:
                - collect screenshots
                - get witness statement
                - save call logs

                PATH 3 — Send No-Contact Request First
                title: Send No-Contact Request First
                description: Send one written boundary request before filing only when danger appears lower.
                recommended_when: Use only in lower-risk cases.
                risk_level: not enforceable and could provoke response
                next_steps:
                - send written request
                - save proof
                - file if ignored or violated
                """)
            ],
            .sayDontSay: [
                exampleNote("Hearing Guidance", caseId: caseId, content: """
                Say:
                - “I am afraid for my safety.”
                - “These incidents happened on these dates.”
                - “Here are the screenshots and call records.”
                - “A neighbour witnessed one incident.”

                Don’t say:
                - “I just want revenge.”
                - “I think they might do something, but I have no facts.”
                - unrelated relationship history
                - speculation
                - insults
                """)
            ]
        ]
    }

    private func exampleNote(_ name: String, caseId: UUID, content: String) -> CaseFile {
        CaseFile(
            name: name,
            type: .note,
            relativePath: "",
            caseId: caseId,
            content: content,
            responseTag: .note
        )
    }

    private func exampleTimelineEvents() -> [TimelineEvent] {
        [
            TimelineEvent(kind: .response, title: "2026-03-01 — Uninvited visit at residence", summary: "Refused to leave for 20 minutes — severity medium", subfolder: .timeline),
            TimelineEvent(kind: .response, title: "2026-03-03 — Text message", summary: "Implied threat “you’ll regret this” — severity high", subfolder: .timeline),
            TimelineEvent(kind: .response, title: "2026-03-05 — Repeated calls", summary: "12 missed calls within 1 hour — severity medium", subfolder: .timeline),
            TimelineEvent(kind: .response, title: "2026-03-07 — Second uninvited visit", summary: "Neighbor witnessed — severity high", subfolder: .timeline),
            TimelineEvent(kind: .response, title: "2026-03-08 — Text message", summary: "Explicit threat “I’m coming over tonight” — severity high", subfolder: .timeline)
        ]
    }

    /// Ensures a case exists (e.g. when opening via invitation link). Adds it with the given title if not present.
    func ensureCaseExists(id: UUID, title: String) {
        guard !cases.contains(where: { $0.id == id }) else { return }
        let folder = normalizedCaseFolder(CaseFolder(id: id, title: title, category: .inProgress))
        cases.append(folder)
        cases = ordered(cases)
        save()
    }

    func renameCase(id: UUID, to newTitle: String) {
        guard let idx = cases.firstIndex(where: { $0.id == id }) else { return }
        guard canMutateCase(id) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cases[idx].title = trimmed
        save()
    }

    /// Court-assigned number after filing; optional until the user enters it.
    func setCourtCaseNumber(id: UUID, number: String?) {
        guard let idx = cases.firstIndex(where: { $0.id == id }) else { return }
        guard canMutateCase(id) else { return }
        let trimmed = number?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        cases[idx].courtCaseNumber = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func deleteCase(id: UUID) {
        guard let idx = cases.firstIndex(where: { $0.id == id }) else { return }
        guard canMutateCase(id) else { return }
        cases.remove(at: idx)
        timelineEvents.removeValue(forKey: id)

        if selectedCase?.id == id {
            selectedCase = startHereFolder ?? cases.first
            selectedFileId = nil
            selectedSubfolder = .evidence
            selectedWorkspaceSection = .chat
        }
        save()
    }

    /// Creates a brand new case folder and selects it in the UI.
    @discardableResult
    func createNewCase(title: String, category: CaseCategory = .inProgress) -> UUID {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "New Case" : trimmed
        let id = UUID()
        var folder = CaseFolder(id: id, title: name, category: category)
        folder = normalizedCaseFolder(folder)
        cases.append(folder)
        cases = ordered(cases)
        selectedCase = folder
        selectedSubfolder = .evidence
        selectedFileId = nil
        selectedWorkspaceSection = .chat
        save()
        return id
    }

    /// Shows every built-in subfolder in the sidebar (Evidence, Timeline, Responses, History, etc.).
    func revealStandardSubfolders(caseId: UUID) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        cases[idx].hiddenSubfolders = [.recordings, .history, .filedDocuments]
        save()
    }

    @discardableResult
    func upsertTextFile(caseId: UUID, subfolder: CaseSubfolder, name: String, content: String) -> UUID? {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return nil }
        guard canMutateCase(caseId) else { return nil }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let existingIndex = cases[idx].subfolders[subfolder]?.firstIndex(where: { $0.name == name }) {
            let fileId = cases[idx].subfolders[subfolder]![existingIndex].id
            updateFile(caseId: caseId, subfolder: subfolder, fileId: fileId, newName: name, newContent: content)
            return fileId
        }

        let file = CaseFile(name: name, type: .note, relativePath: "", content: content)
        addFile(caseId: caseId, subfolder: subfolder, file: file, content: content)
        return file.id
    }

    func events(for caseId: UUID) -> [TimelineEvent] {
        (timelineEvents[caseId] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func addTimelineEvent(_ event: TimelineEvent, caseId: UUID) {
        guard canMutateCase(caseId) else { return }
        var list = timelineEvents[caseId] ?? []
        list.append(event)
        timelineEvents[caseId] = list
        save()
        NotificationCenter.default.post(name: CaseChangeNotifications.timelineChanged, object: caseId)
        if event.kind == .filing {
            CaseProgressStore.shared.markCompleted(caseId: caseId, stageTitle: "File or take action")
        }
    }

    func revertTimeline(to eventId: UUID, caseId: UUID) {
        guard canMutateCase(caseId) else { return }
        guard let list = timelineEvents[caseId],
              let index = list.firstIndex(where: { $0.id == eventId }) else { return }
        timelineEvents[caseId] = Array(list.prefix(through: index))
        save()
        NotificationCenter.default.post(name: CaseChangeNotifications.timelineChanged, object: caseId)
    }

    /// Display name for a folder in a case (custom or default).
    func folderDisplayName(caseId: UUID, subfolder: CaseSubfolder) -> String {
        cases.first(where: { $0.id == caseId })?.displayName(for: subfolder) ?? subfolder.rawValue
    }

    /// Set custom display name for a folder in a case.
    func setFolderDisplayName(caseId: UUID, subfolder: CaseSubfolder, name: String) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cases[idx].customFolderNames.removeValue(forKey: subfolder)
        } else {
            cases[idx].customFolderNames[subfolder] = trimmed
        }
        save()
    }

    func visibleSubfolders(caseId: UUID) -> [CaseSubfolder] {
        guard let folder = cases.first(where: { $0.id == caseId }) else {
            return [.timeline, .evidence, .documents]
        }
        return CaseSubfolder.allCases.filter { !folder.hiddenSubfolders.contains($0) }
    }

    func availableHiddenSubfolders(caseId: UUID) -> [CaseSubfolder] {
        guard let folder = cases.first(where: { $0.id == caseId }) else { return [] }
        return CaseSubfolder.allCases.filter { folder.hiddenSubfolders.contains($0) }
    }

    func setSubfolderHidden(caseId: UUID, subfolder: CaseSubfolder, hidden: Bool) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        if hidden {
            if !cases[idx].hiddenSubfolders.contains(subfolder) {
                cases[idx].hiddenSubfolders.append(subfolder)
            }
            if selectedCase?.id == caseId, selectedSubfolder == subfolder {
                selectedFileId = nil
                selectedSubfolder = .evidence
                selectedWorkspaceSection = .chat
            }
        } else {
            cases[idx].hiddenSubfolders.removeAll { $0 == subfolder }
        }
        save()
    }

    /// Add a document with optional on-disk content (all stored on device).
    func addGeneratedDocument(caseId: UUID, subfolder: CaseSubfolder, name: String, content: String) -> (CaseFile, TimelineEvent)? {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return nil }
        guard canMutateCase(caseId) else { return nil }
        let docId = UUID()
        let relPath = "CaseFiles/\(caseId.uuidString)/\(subfolder.rawValue.replacingOccurrences(of: " ", with: "_"))/\(docId.uuidString).docx"

        let tag: ResponseTag = {
            switch subfolder {
            case .evidence: return .evidence
            case .documents, .filedDocuments: return .draft
            case .response, .strategy, .coaching, .decisionTreePathways, .sayDontSay: return .strategy
            case .history, .timeline: return .note
            default: return .draft
            }
        }()
        let versionNum = parsedTrailingVersionNumber(from: name)
        let group = stripVersionSuffix(from: name)

        let file = CaseFile(
            id: docId,
            name: name,
            type: .docx,
            relativePath: relPath,
            caseId: caseId,
            content: content,
            responseTag: tag,
            versionGroupId: versionNum != nil ? group : nil,
            versionNumber: versionNum
        )
        storage.writeFileContent(caseId: caseId, subfolder: subfolder, fileId: docId, type: .docx, content: content)
        let event = TimelineEvent(kind: .response, title: name, summary: "AI-generated document", documentId: docId, subfolder: subfolder)
        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(file)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        addTimelineEvent(event, caseId: caseId)
        CaseProgressStore.shared.markCompleted(caseId: caseId, stageTitle: "Create document")
        NotificationCenter.default.post(
            name: .contextualMonetizationDocumentGenerated,
            object: nil,
            userInfo: [
                "caseId": caseId.uuidString,
                "fileId": docId.uuidString,
                "subfolder": subfolder.rawValue
            ]
        )
        return (file, event)
    }

    /// Add an image file (stored on device).
    func addImage(caseId: UUID, subfolder: CaseSubfolder, name: String, imageData: Data) -> CaseFile? {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return nil }
        guard canMutateCase(caseId) else { return nil }
        let fileId = UUID()
        let relPath = "CaseFiles/\(caseId.uuidString)/\(subfolder.rawValue.replacingOccurrences(of: " ", with: "_"))/\(fileId.uuidString).jpg"
        storage.writeImage(caseId: caseId, subfolder: subfolder, fileId: fileId, data: imageData)
        let file = CaseFile(id: fileId, name: name, type: .image, relativePath: relPath, caseId: caseId)
        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(file)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        save()
        return file
    }

    /// Add a recording to a recording subfolder (Voice Stories, Witness Statements, etc.). Optionally pass audio data to save to disk.
    func addRecording(caseId: UUID, recordingSubfolder: RecordingSubfolder, name: String, audioData: Data? = nil, durationSeconds: Int? = nil) -> CaseFile? {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return nil }
        guard canMutateCase(caseId) else { return nil }
        let fileId = UUID()
        let subfolderDir = CaseSubfolder.recordings.rawValue.replacingOccurrences(of: " ", with: "_")
        let relPath = "CaseFiles/\(caseId.uuidString)/\(subfolderDir)/\(fileId.uuidString).m4a"
        if let data = audioData {
            storage.writeAudio(caseId: caseId, subfolder: .recordings, fileId: fileId, data: data)
        }
        let file = CaseFile(
            id: fileId,
            name: name.isEmpty ? "Recording \(Date().formatted(date: .abbreviated, time: .shortened))" : name,
            type: .audio,
            relativePath: relPath,
            caseId: caseId,
            recordingSubfolder: recordingSubfolder,
            durationSeconds: durationSeconds
        )
        var folder = cases[idx]
        var files = folder.subfolders[.recordings] ?? []
        files.append(file)
        folder.subfolders[.recordings] = files
        cases[idx] = folder
        save()
        return file
    }

    /// Add any file (e.g. user-created document). Content is stored on device.
    func addFile(caseId: UUID, subfolder: CaseSubfolder, file: CaseFile, content: String?) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        let contentToWrite = content ?? ""
        storage.writeFileContent(caseId: caseId, subfolder: subfolder, fileId: file.id, type: file.type, content: contentToWrite)
        let subfolderDir = subfolder.rawValue.replacingOccurrences(of: " ", with: "_")
        let ext = file.type == .docx ? "docx" : "txt"
        var fileWithPath = file
        fileWithPath.relativePath = "CaseFiles/\(caseId.uuidString)/\(subfolderDir)/\(file.id.uuidString).\(ext)"
        fileWithPath.caseId = caseId
        fileWithPath.content = contentToWrite.isEmpty ? nil : contentToWrite
        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(fileWithPath)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        save()
    }

    /// Add a binary file (PDF/image/other) while still keeping extracted text available in metadata when useful.
    @discardableResult
    func addBinaryFile(
        caseId: UUID,
        subfolder: CaseSubfolder,
        name: String,
        type: CaseFileType,
        data: Data,
        extractedText: String? = nil,
        responseTag: ResponseTag? = nil
    ) -> CaseFile? {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return nil }
        guard canMutateCase(caseId) else { return nil }

        let fileId = UUID()
        storage.writeBinaryFile(caseId: caseId, subfolder: subfolder, fileId: fileId, type: type, data: data)

        let subfolderDir = subfolder.rawValue.replacingOccurrences(of: " ", with: "_")
        let ext: String
        switch type {
        case .pdf: ext = "pdf"
        case .image: ext = "jpg"
        case .audio: ext = "m4a"
        case .docx: ext = "docx"
        case .note: ext = "txt"
        case .other: ext = "bin"
        }

        let file = CaseFile(
            id: fileId,
            name: name,
            type: type,
            relativePath: "CaseFiles/\(caseId.uuidString)/\(subfolderDir)/\(fileId.uuidString).\(ext)",
            createdAt: Date(),
            caseId: caseId,
            recordingSubfolder: nil,
            content: extractedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : extractedText,
            durationSeconds: nil,
            responseTag: responseTag,
            versionGroupId: nil,
            versionNumber: nil
        )

        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(file)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        save()
        return file
    }

    /// Update file name or content (stored on device).
    func updateFile(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID, newName: String?, newContent: String?) {
        guard canMutateCase(caseId) else { return }
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

    func file(for caseId: UUID, subfolder: CaseSubfolder, fileId: UUID) -> CaseFile? {
        files(for: caseId, subfolder: subfolder).first(where: { $0.id == fileId })
    }

    func selectedFile() -> CaseFile? {
        guard let caseId = selectedCase?.id, let fileId = selectedFileId else { return nil }
        return file(for: caseId, subfolder: selectedSubfolder, fileId: fileId)
    }

    // MARK: - File system actions (rename/move/duplicate/delete)

    func renameFile(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateFile(caseId: caseId, subfolder: subfolder, fileId: fileId, newName: trimmed, newContent: nil)
    }

    /// Duplicates a file into the same subfolder by default. For text files, copies `content`.
    /// For images, copies binary data on disk.
    @discardableResult
    func duplicateFile(
        caseId: UUID,
        subfolder: CaseSubfolder,
        fileId: UUID,
        toSubfolder: CaseSubfolder? = nil
    ) -> CaseFile? {
        guard canMutateCase(caseId) else { return nil }
        guard let source = file(for: caseId, subfolder: subfolder, fileId: fileId) else { return nil }
        let destination = toSubfolder ?? subfolder
        let newFileId = UUID()
        let newName = "\(source.name) (Copy)"

        switch source.type {
        case .image:
            let type: CaseFileType = .image
            let oldURL = storage.fileURL(caseId: caseId, subfolder: subfolder, fileId: fileId, type: type)
            guard let data = try? Data(contentsOf: oldURL) else { return nil }

            storage.writeImage(caseId: caseId, subfolder: destination, fileId: newFileId, data: data)
            let relPath = "CaseFiles/\(caseId.uuidString)/\(destination.rawValue.replacingOccurrences(of: " ", with: "_"))/\(newFileId.uuidString).jpg"
            let newFile = CaseFile(
                id: newFileId,
                name: newName,
                type: .image,
                relativePath: relPath,
                createdAt: Date(),
                caseId: caseId,
                recordingSubfolder: nil,
                content: nil,
                durationSeconds: nil,
                responseTag: source.responseTag,
                versionGroupId: nil,
                versionNumber: nil
            )
            appendFile(newFile, to: destination, caseId: caseId)
            selectedCase = cases.first(where: { $0.id == caseId })
            selectedSubfolder = destination
            selectedFileId = newFileId
            return newFile

        case .docx, .note, .other:
            let copiedContent = source.content ?? ""
            let newFile = CaseFile(
                id: newFileId,
                name: newName,
                type: source.type,
                relativePath: "",
                createdAt: Date(),
                caseId: caseId,
                recordingSubfolder: source.recordingSubfolder,
                content: copiedContent.isEmpty ? nil : copiedContent,
                durationSeconds: source.durationSeconds,
                responseTag: source.responseTag,
                versionGroupId: nil,
                versionNumber: nil
            )
            addFile(caseId: caseId, subfolder: destination, file: newFile, content: source.content)
            selectedCase = cases.first(where: { $0.id == caseId })
            selectedSubfolder = destination
            selectedFileId = newFileId
            return newFile

        case .pdf:
            // PDFs are stored as binary; duplication/copying isn't implemented for now.
            return nil

        case .audio:
            // Recordings are managed in the Recordings view; ignore duplication here for now.
            return nil
        }
    }

    /// Moves a file by duplicating into the destination and deleting the original.
    func moveFile(caseId: UUID, fromSubfolder: CaseSubfolder, toSubfolder: CaseSubfolder, fileId: UUID) {
        guard canMutateCase(caseId) else { return }
        guard let _ = duplicateFile(caseId: caseId, subfolder: fromSubfolder, fileId: fileId, toSubfolder: toSubfolder) else { return }
        deleteFile(caseId: caseId, subfolder: fromSubfolder, fileId: fileId)
    }

    func deleteFile(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        guard let file = cases[idx].subfolders[subfolder]?.first(where: { $0.id == fileId }) else { return }

        cases[idx].subfolders[subfolder]?.removeAll { $0.id == fileId }
        save()

        storage.deleteFileContent(caseId: caseId, subfolder: subfolder, fileId: fileId, type: file.type)

        if selectedCase?.id == caseId, selectedSubfolder == subfolder, selectedFileId == fileId {
            selectedFileId = nil
        }

        let event = TimelineEvent(
            kind: .response,
            title: "Deleted: \(file.name)",
            summary: "File removed from this folder",
            createdAt: Date(),
            documentId: fileId,
            subfolder: subfolder
        )
        addTimelineEvent(event, caseId: caseId)
    }

    private func appendFile(_ file: CaseFile, to subfolder: CaseSubfolder, caseId: UUID) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        var folder = cases[idx]
        var files = folder.subfolders[subfolder] ?? []
        files.append(file)
        folder.subfolders[subfolder] = files
        cases[idx] = folder
        save()
    }

    // MARK: - Versioning helpers (AI responses)

    /// Returns the stable "version group" base name for a file.
    /// If `versionGroupId` is present, it wins; otherwise we normalize from the file name.
    func versionGroupBaseName(for file: CaseFile) -> String {
        if let group = file.versionGroupId, !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return group
        }
        return stripVersionSuffix(from: file.name)
    }

    private func stripVersionSuffix(from name: String) -> String {
        // Supports (best-effort):
        // - "<base> v2"
        // - "<base> (v2)"
        // - "<base> Version 2"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = trimmed as NSString

        // Capture group 1 = base name.
        let patterns: [String] = [
            #"(.*)\s*[(]v(\d+)[)]\s*$"#,
            #"(.*)\s*v(\d+)\s*$"#,
            #"(.*)\s+version\s+(\d+)\s*$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let fullRange = NSRange(location: 0, length: ns.length)
            if let m = regex.firstMatch(in: trimmed, options: [], range: fullRange),
               m.numberOfRanges >= 2 {
                let baseRange = m.range(at: 1)
                if baseRange.location != NSNotFound {
                    return ns.substring(with: baseRange).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return trimmed
    }

    /// Computes the next version number for a given (case, subfolder, versionGroup).
    /// Prefers explicit `versionNumber/versionGroupId` metadata; falls back to parsing the file name.
    func nextVersionNumber(caseId: UUID, subfolder: CaseSubfolder, versionGroup: String) -> Int {
        let existing = files(for: caseId, subfolder: subfolder)
        let targetGroup = versionGroup.trimmingCharacters(in: .whitespacesAndNewlines)

        let explicit = existing.compactMap { file -> Int? in
            guard let group = file.versionGroupId else { return nil }
            guard group.trimmingCharacters(in: .whitespacesAndNewlines) == targetGroup else { return nil }
            return file.versionNumber
        }

        let parsedFallback = existing.compactMap { file -> Int? in
            let base = versionGroupBaseName(for: file)
            guard base == targetGroup else { return nil }
            return parsedTrailingVersionNumber(from: file.name)
        }

        let versions = (explicit + parsedFallback).compactMap { $0 }
        return (versions.max() ?? 0) + 1
    }

    private func parsedTrailingVersionNumber(from name: String) -> Int? {
        let ns = name as NSString
        let candidates: [String] = [
            #".*\s*[(]v(\d+)[)]\s*$"#,
            #".*\s*v(\d+)\s*$"#,
            #".*\s+version\s+(\d+)\s*$"#
        ]

        for pattern in candidates {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let fullRange = NSRange(location: 0, length: ns.length)
            if let m = regex.firstMatch(in: name, options: [], range: fullRange),
               m.numberOfRanges >= 2 {
                let digits = ns.substring(with: m.range(at: 1))
                return Int(digits)
            }
        }
        return nil
    }

    /// Creates a new version of `fileId` by copying its content and saving it as the next version.
    /// For now, rollback only supports text-based files (docx/note). Images/audio can be rolled back only
    /// if their `content` field is present (otherwise this is a no-op).
    func rollbackFileVersion(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID) {
        guard canMutateCase(caseId) else { return }
        guard let fileToRollback = file(for: caseId, subfolder: subfolder, fileId: fileId) else { return }
        guard let existingContent = fileToRollback.content else { return }

        let group = versionGroupBaseName(for: fileToRollback)
        let next = nextVersionNumber(caseId: caseId, subfolder: subfolder, versionGroup: group)
        let newFileId = UUID()
        let newName = "\(group) v\(next)"

        let newFile = CaseFile(
            id: newFileId,
            name: newName,
            type: fileToRollback.type,
            relativePath: "",
            createdAt: Date(),
            caseId: caseId,
            recordingSubfolder: fileToRollback.recordingSubfolder,
            content: existingContent,
            durationSeconds: fileToRollback.durationSeconds,
            responseTag: fileToRollback.responseTag,
            versionGroupId: group,
            versionNumber: next
        )

        addFile(caseId: caseId, subfolder: subfolder, file: newFile, content: existingContent)
        selectedCase = cases.first(where: { $0.id == caseId }) ?? selectedCase
        selectedSubfolder = subfolder
        selectedFileId = newFileId

        let event = TimelineEvent(
            kind: .response,
            title: "Rollback: \(newName)",
            summary: "Restored a prior version",
            createdAt: Date(),
            documentId: newFileId,
            subfolder: subfolder
        )
        addTimelineEvent(event, caseId: caseId)
    }

    /// Full URL for download/share (on device).
    func fileURL(for file: CaseFile) -> URL {
        storage.fullURL(relativePath: file.relativePath)
    }

    func fileExistsOnDisk(_ file: CaseFile) -> Bool {
        storage.fileExists(relativePath: file.relativePath)
    }

    // MARK: - Email drafts (Emails workspace; never sent automatically)

    func emailDrafts(for caseId: UUID) -> [EmailDraft] {
        cases.first(where: { $0.id == caseId })?.emailDrafts ?? []
    }

    func addEmailDraft(caseId: UUID, draft: EmailDraft) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        let linked = EmailDraft(id: draft.id, caseId: caseId, subject: draft.subject, body: draft.body, suggestedRecipient: draft.suggestedRecipient, createdAt: draft.createdAt)
        cases[idx].emailDrafts.append(linked)
        save()
    }

    func updateEmailDraft(caseId: UUID, draftId: UUID, subject: String?, body: String?, suggestedRecipient: String?) {
        guard canMutateCase(caseId) else { return }
        guard let idx = cases.firstIndex(where: { $0.id == caseId }),
              let draftIdx = cases[idx].emailDrafts.firstIndex(where: { $0.id == draftId }) else { return }
        let old = cases[idx].emailDrafts[draftIdx]
        let updated = EmailDraft(
            id: old.id,
            caseId: caseId,
            subject: subject ?? old.subject,
            body: body ?? old.body,
            suggestedRecipient: suggestedRecipient ?? old.suggestedRecipient,
            createdAt: old.createdAt
        )
        cases[idx].emailDrafts[draftIdx] = updated
        save()
    }

    // MARK: - Deadlines (from evidence analysis or manual entry)

    func deadlines(for caseId: UUID) -> [LegalDeadline] {
        cases.first(where: { $0.id == caseId })?.deadlines ?? []
    }

    func addDeadlines(_ newDeadlines: [LegalDeadline], caseId: UUID) {
        guard let idx = cases.firstIndex(where: { $0.id == caseId }) else { return }
        guard canMutateCase(caseId) else { return }
        cases[idx].deadlines.append(contentsOf: newDeadlines)
        save()
    }

    @discardableResult
    func addVersionedTextArtifact(
        caseId: UUID,
        subfolder: CaseSubfolder,
        baseName: String,
        content: String,
        responseTag: ResponseTag = .note,
        timelineTitle: String? = nil,
        timelineSummary: String? = nil
    ) -> UUID? {
        guard canMutateCase(caseId) else { return nil }
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, !trimmedContent.isEmpty else { return nil }

        let next = nextVersionNumber(caseId: caseId, subfolder: subfolder, versionGroup: trimmedBase)
        let fileId = UUID()
        let file = CaseFile(
            id: fileId,
            name: "\(trimmedBase) v\(next)",
            type: .note,
            relativePath: "",
            createdAt: Date(),
            caseId: caseId,
            content: trimmedContent,
            responseTag: responseTag,
            versionGroupId: trimmedBase,
            versionNumber: next
        )

        addFile(caseId: caseId, subfolder: subfolder, file: file, content: trimmedContent)
        selectedCase = cases.first(where: { $0.id == caseId }) ?? selectedCase
        selectedSubfolder = subfolder
        selectedFileId = fileId

        if let title = timelineTitle {
            let event = TimelineEvent(
                kind: .response,
                title: title,
                summary: timelineSummary ?? trimmedContent.prefix(180).description,
                createdAt: Date(),
                documentId: fileId,
                subfolder: subfolder
            )
            addTimelineEvent(event, caseId: caseId)
        }

        return fileId
    }
}
