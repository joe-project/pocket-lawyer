import Foundation

// MARK: - Cached snapshot (reused when building context for reasoning)

/// Stored snapshot of case context components so the full prompt does not need to be rebuilt from scratch each time. Messages are always fetched fresh; other fields can be reused from cache.
struct CachedCaseContext {
    var caseAnalysis: CaseAnalysis?
    var strategy: LitigationStrategy?
    var timelineEvents: [TimelineEvent]
    var evidenceSummaries: [String]
    /// Optional; when nil, caller should supply from live data.
    var recordingTranscripts: [String]?

    init(
        caseAnalysis: CaseAnalysis? = nil,
        strategy: LitigationStrategy? = nil,
        timelineEvents: [TimelineEvent] = [],
        evidenceSummaries: [String] = [],
        recordingTranscripts: [String]? = nil
    ) {
        self.caseAnalysis = caseAnalysis
        self.strategy = strategy
        self.timelineEvents = timelineEvents
        self.evidenceSummaries = evidenceSummaries
        self.recordingTranscripts = recordingTranscripts
    }
}

// MARK: - Cache service

/// Stores previously generated case reasoning inputs (analysis, strategy, timeline, evidence summaries). When AI reasoning runs, reuse cached context instead of rebuilding the full prompt each time; combine with fresh messages (and optionally fresh recordings) when building CaseContext.
final class CaseContextCache {

    private var cache: [UUID: CachedCaseContext] = [:]
    private let lock = NSLock()

    /// Returns cached context for the case, if any.
    func get(forCaseId caseId: UUID) -> CachedCaseContext? {
        lock.lock()
        defer { lock.unlock() }
        return cache[caseId]
    }

    /// Stores context for the case. Overwrites any existing entry.
    func set(_ cached: CachedCaseContext, forCaseId caseId: UUID) {
        lock.lock()
        cache[caseId] = cached
        lock.unlock()
    }

    /// Updates only the fields that are non-nil/non-empty in the given cached value; leaves other fields unchanged. Use after reasoning to store new analysis and optionally strategy.
    func update(_ cached: CachedCaseContext, forCaseId caseId: UUID) {
        lock.lock()
        var existing = cache[caseId] ?? CachedCaseContext()
        if let a = cached.caseAnalysis { existing.caseAnalysis = a }
        if let s = cached.strategy { existing.strategy = s }
        if !cached.timelineEvents.isEmpty { existing.timelineEvents = cached.timelineEvents }
        if !cached.evidenceSummaries.isEmpty { existing.evidenceSummaries = cached.evidenceSummaries }
        if let r = cached.recordingTranscripts { existing.recordingTranscripts = r }
        cache[caseId] = existing
        lock.unlock()
    }

    /// Removes cached context for the case.
    func clear(forCaseId caseId: UUID) {
        lock.lock()
        cache.removeValue(forKey: caseId)
        lock.unlock()
    }

    /// Removes all cached context.
    func clearAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
