import Foundation

/// Lightweight NL classification for chat-driven case actions (no network).
enum ChatCaseIntentKind: String, Codable {
    case createCase
    case addToCase
    case addToEvidence
    case addToTimeline
    case addToStrategy
    case addToNotes
    case addToResearch
    case addToDocuments
    case createTask
    case saveLastAssistantReply
    case askForConfirmation
    case normalChatResponse
}

struct ChatCaseIntentParseResult: Equatable {
    let kind: ChatCaseIntentKind
    /// Extracted matter title for create, or name fragment for resolve.
    let titleOrQuery: String?
    let targetSubfolder: CaseSubfolder
    /// When true, user referred to "this/that/it" or attached files should be preferred for evidence.
    let refersToAttachmentOrDemonstrative: Bool
    let confidence: Double
}

enum ChatCaseIntentRouter {

    private static let createLeadPattern = #"(?i)\b(?:create|make|start|open|begin|add\s+a\s+new)\b"#
    private static let containerPattern = #"(?i)\b(?:case|folder|matter|file|thread|chat)\b"#

    private static let addLeadPattern = #"(?i)\b(?:add|put|save|store|attach|file|drop)\b"#

    static func normalizeTitleKey(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: "&", with: "and")
        t = t.replacingOccurrences(of: "versus", with: "vs")
        t = t.replacingOccurrences(of: " v.s. ", with: " vs ")
        t = t.replacingOccurrences(of: " v. ", with: " vs ")
        return t
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "vs" && $0 != "v" }
            .joined(separator: " ")
    }

    static func tokenSet(for s: String) -> Set<String> {
        let parts = normalizeTitleKey(s).split(separator: " ").map(String.init)
        return Set(parts.filter { $0.count > 1 })
    }

    /// Scores how well `query` matches a case title (0...1).
    static func matchScore(query: String, caseTitle: String) -> Double {
        let qRaw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qRaw.isEmpty else { return 0 }
        let qNorm = normalizeTitleKey(qRaw)
        let tNorm = normalizeTitleKey(caseTitle)
        guard !tNorm.isEmpty else { return 0 }

        if tNorm.contains(qNorm) || qNorm.contains(tNorm) { return 1.0 }

        let qTokens = tokenSet(for: qRaw)
        let tTokens = tokenSet(for: caseTitle)
        guard !qTokens.isEmpty, !tTokens.isEmpty else { return 0 }

        let inter = qTokens.intersection(tTokens).count
        if inter == 0 { return 0 }
        let union = qTokens.union(tTokens).count
        let jaccard = Double(inter) / Double(max(union, 1))
        let recall = Double(inter) / Double(max(qTokens.count, 1))
        return max(jaccard, recall * 0.85)
    }

    static func rankedCaseMatches(query: String, cases: [CaseFolder]) -> [(folder: CaseFolder, score: Double)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return cases
            .map { ($0, matchScore(query: trimmed, caseTitle: $0.title)) }
            .filter { $0.1 > 0.22 }
            .sorted { $0.1 > $1.1 }
    }

    static func inferSubfolder(lower: String, hasAttachments: Bool) -> CaseSubfolder {
        if lower.contains("timeline") || lower.contains("chronolog") { return .timeline }
        if lower.contains("say / don't say") || lower.contains("say/don't say") || lower.contains("dont say") || lower.contains("don't say") { return .sayDontSay }
        if lower.contains("decision tree") || lower.contains("pathway") || lower.contains("pathways") { return .decisionTreePathways }
        if lower.contains("coaching") || lower.contains("coach me") { return .coaching }
        if lower.contains("strategy") { return .strategy }
        if lower.contains("response") && !lower.contains("research") { return .response }
        if lower.contains("research") || lower.contains("finding") { return .history }
        if lower.contains("document") || lower.contains("filing") || lower.contains("draft doc") { return .documents }
        if lower.contains("evidence") || lower.contains("proof") || lower.contains("photo") || lower.contains("pic")
            || lower.contains("screenshot") || lower.contains("pdf") || lower.contains("image") {
            return .evidence
        }
        if lower.contains("note") || lower.contains("history") || lower.contains("memo") { return .history }
        if lower.contains("task") || lower.contains("to-do") || lower.contains("todo") || lower.contains("reminder") {
            return .timeline
        }
        return hasAttachments ? .evidence : .history
    }

    private static func extractQuotedOrTrailingTitle(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = trimmed.range(of: #"["']([^"']{2,200})["']"#, options: .regularExpression) {
            let match = String(trimmed[r])
            let inner = match.dropFirst().dropLast()
            let s = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        let lower = trimmed.lowercased()
        let markers = ["called ", "named ", "titled ", "entitled "]
        for m in markers {
            guard let range = lower.range(of: m) else { continue }
            let after = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !after.isEmpty else { continue }
            let cut = after.split { $0 == "." || $0 == "!" || $0 == "?" }.first.map(String.init) ?? after
            let title = cut.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            if title.count >= 2 { return title }
        }
        return nil
    }

    /// Pulls a case name after "to/into the ... case|folder" etc.
    static func extractTargetCaseQuery(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        func firstCapture(pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            let ns = trimmed as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard let m = re.firstMatch(in: trimmed, options: [], range: full),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: trimmed) else { return nil }
            var s = String(trimmed[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(
                of: #"\s+(case|folder|matter|file)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            return s.count >= 2 ? s : nil
        }

        if let q = firstCapture(pattern: #"(?i)\b(?:to|into)\s+(?:the|my|a)\s+(.+?)\s+(?:case|folder|matter|file)\b"#) {
            return q
        }
        if let q = firstCapture(pattern: #"(?i)\bfor\s+(?:the|my)\s+(.+?)\s+(?:case|folder)\b"#) {
            return q
        }

        if lower.contains("credit") && lower.contains("folder") {
            return "credit"
        }
        return nil
    }

    static func refersToDemonstrative(_ lower: String, hasAttachments: Bool) -> Bool {
        if hasAttachments { return true }
        return ["this ", "that ", " this", " that", "it to", "photo", "pic", "picture", "screenshot", "file", "attachment", "upload", "image"]
            .contains { lower.contains($0) }
    }

    static func looksLikeSaveLastAssistant(_ lower: String) -> Bool {
        let phrases = [
            "save that", "save this", "add that", "add this", "store that", "put that",
            "save your last", "save the last", "save your response", "save that response"
        ]
        guard phrases.contains(where: { lower.contains($0) }) else { return false }
        if lower.contains("to the case") || lower.contains("to my case") || lower.contains("into the case") {
            return false
        }
        // Routed to explicit section / target case instead (e.g. "save this to strategy").
        if lower.contains(" to ") || lower.contains(" into ") {
            return false
        }
        return true
    }

    static func parse(rawText: String, hasAttachments: Bool) -> ChatCaseIntentParseResult? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // Create case / folder (avoid "make a note about the case" type sentences)
        let newContainer = lower.range(of: #"(?i)\bnew\s+(case|folder|matter|file|thread)\b"#, options: .regularExpression) != nil
        let titleCue = lower.contains("called") || lower.contains("named") || lower.contains("titled") || lower.contains("entitled")
        let lead = lower.range(of: createLeadPattern, options: .regularExpression) != nil
        let hasFolderWord = lower.contains("folder") || lower.contains("matter") || lower.contains("thread")
        let hasCaseOrFileWord = lower.contains("case") || lower.contains("file")
        let noteLike = lower.contains("note") || lower.contains("memo") || lower.contains("comment")
        let createIntent = newContainer
            || (lead && hasFolderWord && !noteLike)
            || (lead && hasCaseOrFileWord && titleCue && !noteLike)

        if createIntent {
            var title = extractQuotedOrTrailingTitle(from: trimmed)
            if title == nil, lower.contains("this") || lower.contains("here") {
                title = nil
            }
            return ChatCaseIntentParseResult(
                kind: .createCase,
                titleOrQuery: title,
                targetSubfolder: .evidence,
                refersToAttachmentOrDemonstrative: false,
                confidence: title == nil ? 0.72 : 0.9
            )
        }

        // Save last assistant (no explicit target case in message)
        if looksLikeSaveLastAssistant(lower), !lower.contains(" vs "), extractTargetCaseQuery(from: trimmed) == nil {
            let sub = inferSubfolder(lower: lower, hasAttachments: hasAttachments)
            return ChatCaseIntentParseResult(
                kind: .saveLastAssistantReply,
                titleOrQuery: nil,
                targetSubfolder: sub,
                refersToAttachmentOrDemonstrative: false,
                confidence: 0.55
            )
        }

        // Add / save to case (or current)
        let hasAddVerb = lower.range(of: addLeadPattern, options: .regularExpression) != nil
            || lower.contains("file this") || lower.contains("file that")
        let pointsToCase = lower.contains(" to ") || lower.contains(" into ") || lower.contains(" for the ")
        let sectionHints = lower.contains("timeline") || lower.contains("evidence") || lower.contains("strategy")
            || lower.contains("research") || lower.contains("note") || lower.contains("document")
        if hasAddVerb && (pointsToCase || sectionHints || hasAttachments) {
            var query = extractTargetCaseQuery(from: trimmed)
            if lower.contains("this case") || lower.contains("the case") || lower.contains("my case") {
                query = nil
            }
            let sub = inferSubfolder(lower: lower, hasAttachments: hasAttachments)
            let demonstrative = refersToDemonstrative(lower, hasAttachments: hasAttachments)
            let kind: ChatCaseIntentKind = {
                switch sub {
                case .timeline:
                    return lower.contains("task") || lower.contains("todo") || lower.contains("to-do") ? .createTask : .addToTimeline
                case .evidence: return .addToEvidence
                case .response, .strategy, .coaching, .decisionTreePathways, .sayDontSay: return .addToStrategy
                case .history: return lower.contains("research") ? .addToResearch : .addToNotes
                case .documents: return .addToDocuments
                default: return .addToCase
                }
            }()
            return ChatCaseIntentParseResult(
                kind: kind,
                titleOrQuery: query,
                targetSubfolder: sub,
                refersToAttachmentOrDemonstrative: demonstrative,
                confidence: query == nil ? 0.78 : 0.85
            )
        }

        return nil
    }

    static func resolveDisambiguationIndex(from reply: String, optionCount: Int) -> Int? {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let n = Int(t), n >= 1, n <= optionCount { return n - 1 }
        let words = ["first", "1st", "one", "1"]
        if words.contains(t) { return 0 }
        if t == "second" || t == "2" || t == "two" { return min(1, optionCount - 1) }
        if t == "third" || t == "3" { return min(2, optionCount - 1) }
        return nil
    }
}
