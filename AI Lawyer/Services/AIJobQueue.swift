import Foundation

// MARK: - Model

struct AIJob {
    let id: UUID
    let type: String
    let caseId: UUID
}

// MARK: - Service

/// Queues AI tasks so heavy analysis runs asynchronously.
final class AIJobQueue {

    private var queue: [AIJob] = []

    func addJob(_ job: AIJob) {
        queue.append(job)
    }

    func processNext() -> AIJob? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
}
