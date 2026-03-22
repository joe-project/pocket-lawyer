import Foundation

/// Caches case analysis results keyed by a context signature so we can skip re-calling the AI when messages, timeline, and evidence haven't changed.
final class CaseAnalysisResultCache {
    private var cache: [String: CaseAnalysis] = [:]
    private let lock = NSLock()
    private let maxEntries = 50

    /// Returns cached analysis for the signature, if any.
    func get(signature: String) -> CaseAnalysis? {
        lock.lock()
        defer { lock.unlock() }
        return cache[signature]
    }

    /// Stores analysis for the signature. Evicts oldest entries if over capacity.
    func set(_ analysis: CaseAnalysis, signature: String) {
        lock.lock()
        if cache.count >= maxEntries, let firstKey = cache.keys.first {
            cache.removeValue(forKey: firstKey)
        }
        cache[signature] = analysis
        lock.unlock()
    }

    /// Builds a signature from context so identical context produces the same key. When using CaseMemory, pass a fingerprint so cache invalidates when memory changes. nonisolated so it can be called from any concurrency context.
    static nonisolated func signature(
        messageCount: Int,
        timelineCount: Int,
        evidenceCount: Int,
        lastMessageId: UUID?,
        memoryFingerprint: String? = nil
    ) -> String {
        let mem = memoryFingerprint ?? "nomem"
        return "m\(messageCount)_t\(timelineCount)_e\(evidenceCount)_\(lastMessageId?.uuidString ?? "")_\(mem)"
    }
}
