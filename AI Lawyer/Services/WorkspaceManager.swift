import Foundation
import Combine

/// Per-case state: messages, analysis, strategy, deadlines, documents, evidence, emails. Used when a case is selected.
/// Manages multiple cases and provides access to case engines and per-case state. When a case is selected, the workspace loads that case's data.
@MainActor
final class WorkspaceManager: ObservableObject {

    // MARK: - Components (case engines and managers)

    let caseManager: CaseManager
    let conversationManager: ConversationManager
    let caseReasoningEngine: CaseReasoningEngine
    let litigationStrategyEngine: LitigationStrategyEngine
    let caseConfidenceEngine: CaseConfidenceEngine
    let documentEngine: DocumentEngine
    let emailDraftEngine: EmailDraftEngine
    let legalDeadlineTracker: LegalDeadlineTracker
    let evidenceAnalysisEngine: EvidenceAnalysisEngine
    let legalResearchService: LegalResearchService
    let caseCollaborationEngine: CaseCollaborationEngine

    /// Case list and folder storage (documents, evidence, emails, timeline). Shared with UI.
    let caseTreeViewModel: CaseTreeViewModel

    // MARK: - Selection

    @Published var selectedCaseId: UUID?

    /// When true, the user opened the app via an invitation link; restrict UI to this case and to evidence upload + record statements only.
    @Published var isInvitedParticipantMode: Bool = false
    @Published var invitedCaseId: UUID?

    /// Per-case caches for strategy and confidence (engines produce these; we store by case id).
    private var strategyCache: [UUID: LitigationStrategy] = [:]
    private var confidenceCache: [UUID: CaseConfidence] = [:]
    private let cacheLock = NSLock()

    /// Snapshot used to decide if we should run a strategy update (only when evidence, claims, timeline, or damages change).
    private struct StrategyUpdateSnapshot: Equatable {
        let evidenceCount: Int
        let claimsSignature: Set<String>
        let timelineCount: Int
        let damages: String
    }
    private var strategyUpdateSnapshots: [UUID: StrategyUpdateSnapshot] = [:]

    // MARK: - Init and wiring

    init() {
        let aiEngine = AIEngine.shared
        let caseTree = CaseTreeViewModel()
        let caseMgr = CaseManager()
        let docEngine = DocumentEngine(aiEngine: aiEngine)
        let reasoningEngine = CaseReasoningEngine(aiEngine: aiEngine, documentEngine: docEngine)
        let conversation = ConversationManager(caseReasoningEngine: reasoningEngine, aiEngine: aiEngine)
        let litigationEngine = LitigationStrategyEngine(aiEngine: aiEngine)
        let confidenceEngine = CaseConfidenceEngine(aiEngine: aiEngine)
        let emailEngine = EmailDraftEngine(aiEngine: aiEngine)
        let deadlineTracker = LegalDeadlineTracker(caseTreeViewModel: caseTree)
        let evidenceEngine = EvidenceAnalysisEngine(aiEngine: aiEngine)
        let legalResearch = LegalResearchService()

        self.caseTreeViewModel = caseTree
        self.caseManager = caseMgr
        self.conversationManager = conversation
        self.caseReasoningEngine = reasoningEngine
        self.litigationStrategyEngine = litigationEngine
        self.caseConfidenceEngine = confidenceEngine
        self.documentEngine = docEngine
        self.emailDraftEngine = emailEngine
        self.legalDeadlineTracker = deadlineTracker
        self.evidenceAnalysisEngine = evidenceEngine
        self.legalResearchService = legalResearch
        self.caseCollaborationEngine = CaseCollaborationEngine()

        conversationManager.caseManager = caseMgr
        conversationManager.caseTreeViewModel = caseTree

        selectedCaseId = caseTree.selectedCase?.id
    }

    /// Selects a case by id. Updates selectedCaseId and syncs caseTreeViewModel.selectedCase so the sidebar and workspace show the same case.
    func selectCase(_ caseId: UUID?) {
        selectedCaseId = caseId
        if let id = caseId, let folder = caseTreeViewModel.cases.first(where: { $0.id == id }) {
            caseTreeViewModel.selectedCase = folder
            CaseProgressStore.shared.markCompleted(caseId: id, stageTitle: "Viewed case overview")
        } else {
            caseTreeViewModel.selectedCase = nil
        }
    }

    /// Call when the sidebar selects a case (by folder) so WorkspaceManager stays in sync.
    func selectCase(byFolder folder: CaseFolder?) {
        let id = folder?.id
        selectedCaseId = id
        caseTreeViewModel.selectedCase = folder
        if let id {
            CaseProgressStore.shared.markCompleted(caseId: id, stageTitle: "Viewed case overview")
        }
    }

    /// Applies an invitation token (e.g. from open URL). Resolves case id, selects that case, and sets invited-participant mode so access is restricted to evidence upload and record statements.
    func applyInvitation(token: String) -> Bool {
        guard let caseId = caseCollaborationEngine.resolveInvitation(token: token) else { return false }
        invitedCaseId = caseId
        isInvitedParticipantMode = true
        selectCase(caseId)
        caseTreeViewModel.ensureCaseExists(id: caseId, title: "Invited case")
        return true
    }

    /// Clears invited-participant mode (e.g. when user signs in as owner or leaves the invited flow).
    func clearInvitedParticipantMode() {
        isInvitedParticipantMode = false
        invitedCaseId = nil
    }

    // MARK: - Strategy updates (only when evidence, claims, timeline, or damages change)

    /// Call after case analysis is updated. Runs litigation strategy update only when new evidence is added, a new claim is detected, timeline events change, or damages estimates change. Strategy API call runs off the main actor; UI is updated only when the response returns.
    func considerStrategyUpdate(caseId: UUID) async {
        guard let analysis = caseManager.getCase(byId: caseId)?.analysis else { return }
        let evidenceFiles = caseTreeViewModel.files(for: caseId, subfolder: .evidence)
        let evidenceCount = evidenceFiles.count
        let claimsSignature = Set(
            analysis.claims
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let timelineCount = analysis.timeline.count
        let damages = analysis.estimatedDamages.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = StrategyUpdateSnapshot(
            evidenceCount: evidenceCount,
            claimsSignature: claimsSignature,
            timelineCount: timelineCount,
            damages: damages
        )
        if let existing = strategyUpdateSnapshots[caseId], existing == current {
            return
        }
        let evidenceSummaries: [EvidenceAnalysis] = evidenceFiles.map { file in
            let summary = (file.content?.trimmingCharacters(in: .whitespacesAndNewlines))
                .map { $0.count > 2000 ? String($0.prefix(2000)) + "…" : $0 }
                ?? file.name
            return EvidenceAnalysis(
                summary: summary,
                violations: [],
                damages: nil,
                timelineEvents: [],
                deadlines: [],
                missingEvidence: nil
            )
        }
        let engine = litigationStrategyEngine
        let timeline = analysis.timeline
        Task.detached { [weak self] in
            do {
                let strategy = try await engine.updateStrategy(
                    caseAnalysis: analysis,
                    evidenceSummaries: evidenceSummaries,
                    timeline: timeline
                )
                await MainActor.run {
                    self?.setStrategy(strategy, forCaseId: caseId)
                    self?.strategyUpdateSnapshots[caseId] = current
                }
            } catch {
                print("Strategy update failed:", error.localizedDescription)
            }
        }
    }

    /// Returns formatted legal references (citations and summaries from CourtListener, GovInfo, LII) for the case so they can be included in AI context and responses. Uses case analysis to detect topics and query online legal sources.
    func legalResearchAppendix(for caseId: UUID) async -> String {
        guard let analysis = caseManager.getCase(byId: caseId)?.analysis else { return "" }
        let response = await legalResearchService.research(analysis: analysis)
        return response.promptAppendix
    }

    // MARK: - Uploaded evidence: auto-analyze and update case

    /// When a document is uploaded to Evidence: extract text (caller provides it), run EvidenceAnalysisEngine off the main actor, then attach results and refresh CaseReasoningEngine on main.
    func processUploadedEvidenceDocument(caseId: UUID, documentText: String) async {
        let trimmed = documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        CaseProgressStore.shared.markCompleted(caseId: caseId, stageTitle: "Upload evidence")
        let engine = evidenceAnalysisEngine
        typealias EvidenceResult = Result<EvidenceAnalysis, Error>
        let task = Task.detached {
            do {
                let analysis = try await engine.analyze(documentText: trimmed)
                return EvidenceResult.success(analysis)
            } catch {
                return EvidenceResult.failure(error)
            }
        }
        let result: EvidenceResult = await task.value
        switch result {
        case .success(let evidenceAnalysis):
            let title = caseTreeViewModel.cases.first(where: { $0.id == caseId })?.title ?? "Case"
            caseManager.ensureCaseExists(caseId: caseId, title: title)
            let currentAnalysis = caseManager.getCase(byId: caseId)?.analysis
            let updatedAnalysis = evidenceAnalysisEngine.apply(
                evidenceAnalysis,
                toCaseId: caseId,
                caseTreeViewModel: caseTreeViewModel,
                currentAnalysis: currentAnalysis
            )
            caseManager.setAnalysis(updatedAnalysis, forCaseId: caseId)
            Task { @MainActor in
                conversationManager.enqueueReasoning(caseId: caseId)
            }
        case .failure(let error):
            print("Evidence analysis failed:", error.localizedDescription)
        }
    }

    // MARK: - Per-case state (for the selected case or any case id)

    /// Full case state for AI reasoning: participants, messages, evidence, timeline events, claims, documents, email drafts, deadlines, litigation strategy. All entities linked by caseId.
    func state(for caseId: UUID) -> CaseState {
        let folder = caseTreeViewModel.cases.first(where: { $0.id == caseId })
        let title = folder?.title ?? ""
        let participants = caseCollaborationEngine.participants(for: caseId)
        let messages = conversationManager.messagesForCase(caseId: caseId)
        let evidence = caseTreeViewModel.files(for: caseId, subfolder: .evidence)
        let timelineEvents = caseTreeViewModel.events(for: caseId)
        let documents = caseTreeViewModel.files(for: caseId, subfolder: .documents)
        let emailDrafts = caseTreeViewModel.emailDrafts(for: caseId)
        let deadlines = legalDeadlineTracker.deadlines(for: caseId)
        let analysis = caseManager.getCase(byId: caseId)?.analysis
        let claims = (analysis?.claims ?? []).map { Claim(caseId: caseId, text: $0) }
        return CaseState(
            caseId: caseId,
            title: title,
            participants: participants,
            messages: messages,
            evidence: evidence,
            timelineEvents: timelineEvents,
            claims: claims,
            documents: documents,
            emailDrafts: emailDrafts,
            deadlines: deadlines,
            litigationStrategy: strategyForCase(caseId),
            analysis: analysis,
            confidence: confidenceForCase(caseId),
            evidenceAlerts: evidenceAlertsForCase(caseId),
            legalArguments: legalArgumentsForCase(caseId)
        )
    }

    /// State for the currently selected case, or nil if none selected.
    var currentCaseState: CaseState? {
        guard let id = selectedCaseId else { return nil }
        return state(for: id)
    }

    /// Selected case folder (convenience).
    var selectedCaseFolder: CaseFolder? {
        caseTreeViewModel.selectedCase
    }

    // MARK: - Strategy and confidence (cached per case)

    func strategyForCase(_ caseId: UUID) -> LitigationStrategy? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return strategyCache[caseId]
    }

    func setStrategy(_ strategy: LitigationStrategy?, forCaseId caseId: UUID) {
        cacheLock.lock()
        if let s = strategy {
            strategyCache[caseId] = s
        } else {
            strategyCache.removeValue(forKey: caseId)
        }
        cacheLock.unlock()
        objectWillChange.send()
    }

    func confidenceForCase(_ caseId: UUID) -> CaseConfidence? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return confidenceCache[caseId]
    }

    func setConfidence(_ confidence: CaseConfidence?, forCaseId caseId: UUID) {
        cacheLock.lock()
        if let c = confidence {
            confidenceCache[caseId] = c
        } else {
            confidenceCache.removeValue(forKey: caseId)
        }
        cacheLock.unlock()
        objectWillChange.send()
    }

    // MARK: - Evidence alerts (verification results per case)

    private var evidenceAlertsCache: [UUID: [EvidenceAlert]] = [:]

    func evidenceAlertsForCase(_ caseId: UUID) -> [EvidenceAlert] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return evidenceAlertsCache[caseId] ?? []
    }

    func setEvidenceAlerts(_ alerts: [EvidenceAlert], forCaseId caseId: UUID) {
        cacheLock.lock()
        evidenceAlertsCache[caseId] = alerts
        cacheLock.unlock()
        objectWillChange.send()
    }

    // MARK: - Legal arguments (IRAC per case)

    private var legalArgumentsCache: [UUID: [LegalArgument]] = [:]

    func legalArgumentsForCase(_ caseId: UUID) -> [LegalArgument] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return legalArgumentsCache[caseId] ?? []
    }

    func setLegalArguments(_ arguments: [LegalArgument], forCaseId caseId: UUID) {
        cacheLock.lock()
        legalArgumentsCache[caseId] = arguments
        cacheLock.unlock()
        objectWillChange.send()
    }
}
