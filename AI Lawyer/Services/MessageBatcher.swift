import Foundation

/// A batch of messages collected for periodic case reasoning updates.
struct MessageBatch {
    let messages: [Message]
    let createdAt: Date
}

/// Batches user messages and triggers case reasoning when the batch is full (e.g. every 3 messages) or when the oldest message is stale, so the UI isn't blocked on every keystroke and reasoning runs in the background.
final class MessageBatcher {
    private var pendingMessages: [Message] = []
    private let batchSize = 3
    private let maxAgeSeconds: TimeInterval = 45

    func addMessage(_ message: Message) {
        pendingMessages.append(message)
    }

    /// Returns true when the batch has enough messages to process (≥ batchSize) or the oldest pending message is older than maxAgeSeconds.
    func shouldProcessBatch() -> Bool {
        if pendingMessages.count >= batchSize { return true }
        guard let oldest = pendingMessages.first else { return false }
        return Date().timeIntervalSince(oldest.timestamp) >= maxAgeSeconds
    }

    /// Removes and returns the current pending messages. Call after shouldProcessBatch() is true; then trigger reasoning for the case(s) in the returned batch.
    func flushBatch() -> [Message] {
        let batch = pendingMessages
        pendingMessages.removeAll()
        return batch
    }
}
