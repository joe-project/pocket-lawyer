import Foundation

/// A small, display-focused brief for the case workspace header card.
struct CaseBrief: Codable, Equatable {
    var summary: String
    var damagesEstimate: String?
    var nextRecommendedStep: String
}

/// Builds a CaseBrief from the latest case state (analysis + memory).
final class CaseBriefEngine {

    func generateBrief(analysis: CaseAnalysis, memory: CaseMemory) -> CaseBrief {
        let summary = analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let damages = (memory.damagesEstimate?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let nextStep = (analysis.nextSteps.first?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "Continue gathering evidence and consult an attorney."

        return CaseBrief(
            summary: summary,
            damagesEstimate: damages ?? (analysis.estimatedDamages.isEmpty ? nil : analysis.estimatedDamages),
            nextRecommendedStep: nextStep
        )
    }
}

/// Persists and retrieves `CaseBrief` per case.
final class CaseBriefStore {

    static let shared = CaseBriefStore()

    private let fileManager = FileManager.default
    private let fileName = "caseBriefs.json"
    private let queue = DispatchQueue(label: "com.ailawyer.casebriefstore", attributes: .concurrent)

    private var cache: [UUID: CaseBrief] = [:]

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL {
        documentsURL.appendingPathComponent(fileName)
    }

    private struct Persisted: Codable {
        let briefs: [String: CaseBrief] // UUID string -> CaseBrief
    }

    private init() {
        queue.sync(flags: .barrier) { loadFromDiskSync() }
    }

    private func loadFromDiskSync() {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else {
            cache = [:]
            return
        }
        var loaded: [UUID: CaseBrief] = [:]
        for (key, brief) in persisted.briefs {
            if let uuid = UUID(uuidString: key) {
                loaded[uuid] = brief
            }
        }
        cache = loaded
    }

    private func saveToDisk(_ snapshot: [UUID: CaseBrief]) {
        let dict = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key.uuidString, $0.value) })
        let persisted = Persisted(briefs: dict)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL)
    }

    func brief(for caseId: UUID) -> CaseBrief? {
        queue.sync { cache[caseId] }
    }

    func setBrief(_ brief: CaseBrief, for caseId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.cache[caseId] = brief
            self.saveToDisk(self.cache)
        }
    }
}

