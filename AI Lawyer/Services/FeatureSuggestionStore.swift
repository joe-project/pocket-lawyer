import Foundation

struct FeatureSuggestion: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Local-only storage for feature suggestions. Keeps a queue for future backend submission.
final class FeatureSuggestionStore {
    static let shared = FeatureSuggestionStore()

    private let fileManager = FileManager.default
    private let fileName = "featureSuggestions.json"
    private let queue = DispatchQueue(label: "com.ailawyer.featuresuggestions", attributes: .concurrent)

    private var cache: [FeatureSuggestion] = []

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL {
        documentsURL.appendingPathComponent(fileName)
    }

    private init() {
        queue.sync(flags: .barrier) { loadFromDiskSync() }
    }

    private func loadFromDiskSync() {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FeatureSuggestion].self, from: data) else {
            cache = []
            return
        }
        cache = decoded
    }

    private func saveToDisk(_ snapshot: [FeatureSuggestion]) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL)
    }

    func all() -> [FeatureSuggestion] {
        queue.sync { cache }.sorted { $0.createdAt > $1.createdAt }
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.cache.append(FeatureSuggestion(text: trimmed))
            self.saveToDisk(self.cache)
        }
    }
}

