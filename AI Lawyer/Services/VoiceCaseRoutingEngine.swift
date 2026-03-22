import Foundation

// MARK: - Model

/// Result of routing a voice command + file to a case. Use to attach the file and update the timeline.
struct VoiceRoutingResult {
    /// Matched case id, or nil if no case matched.
    let caseId: UUID?
    /// Whether to store as Evidence or Recordings.
    let subfolder: CaseSubfolder
    /// For evidence: category from EvidenceCategorizationEngine (e.g. "photos", "documents"). Nil for recordings.
    let evidenceCategory: String?
    /// Short description for a timeline event (e.g. "Added photo for case about landlord").
    let timelineTitle: String
}

// MARK: - Engine

/// Routes evidence and recordings to the correct case using voice command transcripts. Matches transcript keywords to case titles and determines subfolder (evidence vs recordings) and evidence category.
final class VoiceCaseRoutingEngine {
    private let categorizationEngine = EvidenceCategorizationEngine()

    /// Stopwords excluded when matching transcript to case titles.
    private static let stopwords: Set<String> = [
        "this", "the", "for", "about", "my", "a", "an", "is", "to", "relates", "relating",
        "recording", "recordings", "photo", "photos", "file", "files", "evidence", "case", "cases"
    ]

    /// Minimum number of overlapping significant words to consider a case a match.
    private static let minOverlapCount = 1

    /// Routes a voice transcript and optional file to a case. Use the result to attach the file and add a timeline event.
    /// - Parameters:
    ///   - transcript: User voice input (e.g. "This photo is for the case about my landlord.")
    ///   - caseTitles: Existing cases as (id, title).
    ///   - fileName: Optional uploaded file name (used for evidence category and timeline text).
    /// - Returns: Matched case id (if any), subfolder (evidence vs recordings), evidence category, and timeline title.
    func route(
        transcript: String,
        caseTitles: [(id: UUID, title: String)],
        fileName: String? = nil
    ) -> VoiceRoutingResult {
        let transcriptWords = significantWords(in: transcript)
        let subfolder = inferSubfolder(from: transcript)
        let evidenceCategory: String? = subfolder == .evidence && fileName != nil
            ? categorizationEngine.categorize(fileName: fileName!)
            : nil
        let timelineTitle = buildTimelineTitle(transcript: transcript, fileName: fileName, subfolder: subfolder)

        guard !caseTitles.isEmpty, !transcriptWords.isEmpty else {
            return VoiceRoutingResult(
                caseId: nil,
                subfolder: subfolder,
                evidenceCategory: evidenceCategory,
                timelineTitle: timelineTitle
            )
        }

        var bestMatch: (id: UUID, score: Int)?
        for pair in caseTitles {
            let titleWords = significantWords(in: pair.title)
            let overlap = transcriptWords.intersection(titleWords).count
            if overlap >= Self.minOverlapCount {
                if bestMatch == nil || overlap > bestMatch!.score {
                    bestMatch = (pair.id, overlap)
                }
            }
        }

        return VoiceRoutingResult(
            caseId: bestMatch?.id,
            subfolder: subfolder,
            evidenceCategory: evidenceCategory,
            timelineTitle: timelineTitle
        )
    }

    /// Infers whether the user is attaching evidence (photo, document) or a recording from the transcript.
    private func inferSubfolder(from transcript: String) -> CaseSubfolder {
        let lower = transcript.lowercased()
        if lower.contains("recording") || lower.contains("voice") || lower.contains("statement") || lower.contains("witness") {
            return .recordings
        }
        return .evidence
    }

    /// Extracts significant (non-stopword) words from text for matching.
    private func significantWords(in text: String) -> Set<String> {
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return Set(normalized.filter { !Self.stopwords.contains($0) })
    }

    /// Builds a short timeline event title from the transcript and file.
    private func buildTimelineTitle(transcript: String, fileName: String?, subfolder: CaseSubfolder) -> String {
        let filePart = fileName.map { "\($0)" } ?? "file"
        if subfolder == .recordings {
            return "Added recording: \(filePart)"
        }
        let snippet = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(60)
        if snippet.isEmpty {
            return "Added evidence: \(filePart)"
        }
        return "Added \(filePart) — \"\(snippet)\(transcript.count > 60 ? "…" : "")\""
    }
}

// MARK: - Apply result (attach file + timeline)

extension VoiceCaseRoutingEngine {
    /// Attaches the file to the routed case and adds a timeline event. Call after `route(transcript:caseTitles:fileName:)` when `result.caseId` is non-nil.
    /// - Returns: The case id the file was attached to, or nil if result had no case or apply failed.
    @discardableResult
    func apply(
        result: VoiceRoutingResult,
        file: CaseFile,
        content: String?,
        caseTreeViewModel: CaseTreeViewModel
    ) -> UUID? {
        guard let caseId = result.caseId else { return nil }
        caseTreeViewModel.addFile(caseId: caseId, subfolder: result.subfolder, file: file, content: content)
        let event = TimelineEvent(
            kind: .task,
            title: result.timelineTitle,
            summary: "Voice-routed \(result.subfolder.rawValue)",
            documentId: file.id,
            subfolder: result.subfolder
        )
        caseTreeViewModel.addTimelineEvent(event, caseId: caseId)
        return caseId
    }
}
