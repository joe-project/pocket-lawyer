import Foundation

// MARK: - Input / Result

/// Represents an uploaded file for hands-free evidence flow (name, type, optional text content).
struct HandsFreeUpload {
    let name: String
    let type: CaseFileType
    let content: String?

    init(name: String, type: CaseFileType, content: String? = nil) {
        self.name = name
        self.type = type
        self.content = content
    }
}

/// Result of processing a hands-free evidence upload (file + voice explanation).
struct HandsFreeProcessResult {
    let success: Bool
    let caseId: UUID?
    let message: String
}

// MARK: - Engine

/// Orchestrates the hands-free evidence workflow: user uploads a file, records a voice explanation, and the system routes the file to the right case, categorizes it, stores it, updates the timeline, and refreshes case analysis.
final class HandsFreeEvidenceEngine {
    private let voiceRoutingEngine = VoiceCaseRoutingEngine()
    private let evidenceAnalysisEngine = EvidenceAnalysisEngine()

    /// Evidence categories used for categorization (aligned with EvidenceCategorizationEngine).
    static let evidenceCategories = ["photos", "documents", "messages", "witness statements", "videos"]

    /// Runs the full workflow: analyze transcript → determine case → categorize → store file → update timeline → run evidence analysis on text (if any) → enqueue case reasoning.
    /// - Parameters:
    ///   - file: Uploaded file (name, type, optional text content for documents).
    ///   - transcript: User's voice explanation (e.g. "This photo is for the case about my landlord.").
    ///   - caseTreeViewModel: Case list and file storage.
    ///   - conversationManager: Used to enqueue case reasoning so analysis updates.
    ///   - caseManager: Used to get/set case analysis when applying evidence analysis.
    /// - Returns: Success flag, case id the file was attached to (if any), and a short message for the UI.
    func process(
        file: HandsFreeUpload,
        transcript: String,
        caseTreeViewModel: CaseTreeViewModel,
        conversationManager: ConversationManager,
        caseManager: CaseManager
    ) async -> HandsFreeProcessResult {
        let caseTitles = caseTreeViewModel.cases.map { (id: $0.id, title: $0.title) }
        let routingResult = voiceRoutingEngine.route(
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            caseTitles: caseTitles,
            fileName: file.name
        )

        let caseId: UUID? = routingResult.caseId ?? caseTreeViewModel.selectedCase?.id
        guard let targetCaseId = caseId else {
            return HandsFreeProcessResult(
                success: false,
                caseId: nil,
                message: "No case matched and no case selected. Select a case or say which case this is for."
            )
        }

        var caseFile = CaseFile(
            id: UUID(),
            name: file.name,
            type: file.type,
            relativePath: "",
            createdAt: Date(),
            caseId: targetCaseId
        )
        if routingResult.subfolder == .recordings {
            caseFile.recordingSubfolder = inferRecordingSubfolder(from: transcript)
        }

        await MainActor.run {
            _ = voiceRoutingEngine.apply(
                result: routingResult,
                file: caseFile,
                content: file.content,
                caseTreeViewModel: caseTreeViewModel
            )
        }

        if routingResult.subfolder == .evidence,
           let text = file.content,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let evidenceAnalysis = try await evidenceAnalysisEngine.analyze(documentText: text)
                await MainActor.run {
                    let currentAnalysis = caseManager.getCase(byId: targetCaseId)?.analysis
                    let updatedAnalysis = evidenceAnalysisEngine.apply(
                        evidenceAnalysis,
                        toCaseId: targetCaseId,
                        caseTreeViewModel: caseTreeViewModel,
                        currentAnalysis: currentAnalysis
                    )
                    caseManager.setAnalysis(updatedAnalysis, forCaseId: targetCaseId)
                }
            } catch {
                return HandsFreeProcessResult(
                    success: true,
                    caseId: targetCaseId,
                    message: "File added to case. Evidence analysis failed: \(error.localizedDescription)"
                )
            }
        }

        await MainActor.run {
            conversationManager.enqueueReasoning(caseId: targetCaseId)
        }

        let caseTitle = caseTreeViewModel.cases.first(where: { $0.id == targetCaseId })?.title ?? "Case"
        return HandsFreeProcessResult(
            success: true,
            caseId: targetCaseId,
            message: "Added “\(file.name)” to \(caseTitle). Timeline and case analysis will update shortly."
        )
    }

    /// Infers Voice Stories vs Witness Statements etc. from the transcript.
    private func inferRecordingSubfolder(from transcript: String) -> RecordingSubfolder {
        let lower = transcript.lowercased()
        if lower.contains("witness") || lower.contains("statement") {
            return .witnessStatements
        }
        if lower.contains("deposition") {
            return .depositions
        }
        if lower.contains("note") {
            return .notes
        }
        return .voiceStories
    }
}
