import Foundation

/// Persists and updates case progress stages (e.g. "Story Recorded") per case.
/// Used to keep progress stable across launches and update it automatically as the user interacts.
final class CaseProgressStore {

    static let shared = CaseProgressStore()

    private let fileManager = FileManager.default
    private let engine = CaseProgressEngine()
    private let fileName = "caseProgress.json"

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL {
        documentsURL.appendingPathComponent(fileName)
    }

    /// caseId -> completed stage titles
    private var completedByCase: [UUID: Set<String>] = [:]
    private let queue = DispatchQueue(label: "com.ailawyer.caseprogressstore", attributes: .concurrent)

    private init() {
        queue.sync(flags: .barrier) { loadFromDiskSync() }
    }

    private struct Persisted: Codable {
        let completed: [String: [String]] // UUID string -> stage titles
    }

    private func loadFromDiskSync() {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else {
            completedByCase = [:]
            return
        }
        var result: [UUID: Set<String>] = [:]
        for (key, titles) in persisted.completed {
            if let uuid = UUID(uuidString: key) {
                result[uuid] = Set(titles)
            }
        }
        completedByCase = result
    }

    private func saveToDisk(_ snapshot: [UUID: Set<String>]) {
        let dict = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key.uuidString, Array($0.value).sorted()) })
        let persisted = Persisted(completed: dict)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL)
    }

    /// Returns the full CaseProgress model for display, marking saved stage titles as completed.
    func progress(for caseId: UUID) -> CaseProgress {
        let completed = queue.sync { completedByCase[caseId] ?? [] }
        var progress = engine.generateInitialProgress()
        progress.stages = progress.stages.map { stage in
            var updated = stage
            updated.completed = completed.contains(stage.title)
            return updated
        }
        return progress
    }

    /// Marks a stage title as completed for the case and persists it.
    func markCompleted(caseId: UUID, stageTitle: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var set = self.completedByCase[caseId] ?? []
            set.insert(stageTitle)
            self.completedByCase[caseId] = set
            self.saveToDisk(self.completedByCase)
        }
    }

    /// Clears all progress for a case (e.g. when deleted).
    func clear(caseId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.completedByCase.removeValue(forKey: caseId)
            self.saveToDisk(self.completedByCase)
        }
    }
}

