import Foundation

/// Persists the current case memory per case so it can be reused without recomputing.
/// Updates memory when new information arrives and supports fast retrieval for AI reasoning.
final class CaseMemoryStore {

    static let shared = CaseMemoryStore()

    private let fileManager = FileManager.default
    private let engine = CaseMemoryEngine()
    private let memoryFileName = "caseMemory.json"

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var memoryFileURL: URL {
        documentsURL.appendingPathComponent(memoryFileName)
    }

    /// In-memory cache for fast retrieval. Keys are case UUIDs.
    private var cache: [UUID: CaseMemory] = [:]
    private let queue = DispatchQueue(label: "com.ailawyer.casememorystore", attributes: .concurrent)

    private init() {
        queue.sync(flags: .barrier) {
            loadFromDiskSync()
        }
    }

    // MARK: - Persistence

    private struct PersistedMemories: Codable {
        /// UUID string -> CaseMemory
        let memories: [String: CaseMemory]
    }

    /// Call only from inside the barrier queue (e.g. from init).
    private func loadFromDiskSync() {
        guard fileManager.fileExists(atPath: memoryFileURL.path),
              let data = try? Data(contentsOf: memoryFileURL),
              let persisted = try? JSONDecoder().decode(PersistedMemories.self, from: data) else {
            cache = [:]
            return
        }
        var loaded: [UUID: CaseMemory] = [:]
        for (key, memory) in persisted.memories {
            if let uuid = UUID(uuidString: key) {
                loaded[uuid] = memory
            }
        }
        cache = loaded
    }

    /// Pass a snapshot when calling from inside the barrier queue to avoid deadlock.
    private func saveToDisk(_ snapshot: [UUID: CaseMemory]? = nil) {
        let toSave: [UUID: CaseMemory] = snapshot ?? queue.sync { cache }
        let dict = Dictionary(uniqueKeysWithValues: toSave.map { ($0.key.uuidString, $0.value) })
        let persisted = PersistedMemories(memories: dict)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: memoryFileURL)
    }

    // MARK: - Public API

    /// Retrieves the stored memory for the case. Fast in-memory lookup. Returns nil if no memory has been stored yet.
    func memory(for caseId: UUID) -> CaseMemory? {
        queue.sync { cache[caseId] }
    }

    /// Returns the current memory for the case, or an empty memory if none exists. Use this when you need a non-optional value for reasoning.
    func memoryOrEmpty(for caseId: UUID) -> CaseMemory {
        memory(for: caseId) ?? CaseMemory()
    }

    /// Merges a user message and locally extracted workflow payload into memory synchronously (no AI round-trip).
    /// Used when bootstrapping a new case so prompts have immediate structured context.
    func merge(message: Message, payload: CaseUpdatePayload) {
        guard let caseId = message.caseId else { return }
        var memory = memoryOrEmpty(for: caseId)

        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty, trimmedContent != "(attachment)" {
            memory.events = mergeStringLists(memory.events, [trimmedContent])
        }
        for name in message.attachmentNames where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            memory.evidence = mergeStringLists(memory.evidence, ["Attachment: \(name)"])
        }

        if let summary = payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            memory.claims = mergeStringLists(memory.claims, [summary])
        }
        if let caseType = payload.caseType?.trimmingCharacters(in: .whitespacesAndNewlines), !caseType.isEmpty {
            memory.claims = mergeStringLists(memory.claims, ["Case type: \(caseType)"])
        }

        for fact in payload.extractedFacts {
            let value = fact.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            switch fact.kind {
            case .person:
                memory.people = mergeStringLists(memory.people, [value])
            case .date, .location, .deadline, .venue, .requestedAction:
                memory.events = mergeStringLists(memory.events, [value])
            case .claim, .injury, .caseType:
                memory.claims = mergeStringLists(memory.claims, [value])
            case .evidence, .document:
                memory.evidence = mergeStringLists(memory.evidence, [value])
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        for event in payload.timelineEvents {
            let desc = event.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty else { continue }
            let line: String
            if let date = event.date {
                line = "\(dateFormatter.string(from: date)): \(desc)"
            } else {
                line = desc
            }
            memory.events = mergeStringLists(memory.events, [line])
        }

        for item in payload.evidenceItems {
            var line = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                line = line.isEmpty ? notes : "\(line) — \(notes)"
            }
            guard !line.isEmpty else { continue }
            memory.evidence = mergeStringLists(memory.evidence, [line])
        }

        for requirement in payload.documentRequirements {
            let title = requirement.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            memory.evidence = mergeStringLists(memory.evidence, ["Document needed: \(title)"])
        }

        for note in payload.strategyNotes {
            let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            memory.claims = mergeStringLists(memory.claims, [text])
        }

        for pathway in payload.decisionTreePathways {
            let title = pathway.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            memory.events = mergeStringLists(memory.events, ["Pathway option: \(title)"])
        }

        setMemory(memory, forCaseId: caseId)
    }

    /// Updates the case memory with new information using the AI engine, persists the result, and returns the updated memory.
    /// Call when new messages, evidence, or other information arrive so the memory stays current without recomputing from full history.
    func updateMemory(caseId: UUID, newInformation: String) async throws -> CaseMemory {
        let current = memoryOrEmpty(for: caseId)
        let updated = try await engine.updateMemory(memory: current, newInformation: newInformation)
        setMemory(updated, forCaseId: caseId)
        return updated
    }

    /// Stores a memory for the case (e.g. after parsing from an initial case analysis). Persists immediately.
    func setMemory(_ memory: CaseMemory, forCaseId caseId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.cache[caseId] = memory
            self.saveToDisk(self.cache)
        }
    }

    /// Removes stored memory for the case. Use when a case is deleted.
    func removeMemory(forCaseId caseId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.cache.removeValue(forKey: caseId)
            self.saveToDisk(self.cache)
        }
    }

    private func mergeStringLists(_ existing: [String], _ newItems: [String]) -> [String] {
        var result = existing
        var seen = Set(
            existing
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        for item in newItems {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}
