import Foundation

// MARK: - Model

/// A timeline event produced by reconstructing the case from messages and evidence. Includes an optional date, description, and source (e.g. "message", "evidence", "ai").
struct ReconstructedTimelineEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date?
    let description: String
    let source: String

    init(id: UUID = UUID(), date: Date?, description: String, source: String) {
        self.id = id
        self.date = date
        self.description = description
        self.source = source
    }
}

// MARK: - Parser

/// Parses AI timeline reconstruction response into ReconstructedTimelineEvent values.
enum TimelineParser {
    private static let sectionMarkers = ["TIMELINE", "TIMELINE OF EVENTS", "CHRONOLOGICAL TIMELINE", "KEY EVENTS", "**timeline**"]

    static func parse(_ response: String) -> [ReconstructedTimelineEvent] {
        let content = sectionContent(response)
        return parseTimelineLines(content)
    }

    private static func sectionContent(_ text: String) -> String {
        for marker in sectionMarkers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                let after = String(text[range.upperBound...])
                let endMarkers = ["\n\n\n", "---", "NEXT STEPS", "SUMMARY", "**next"]
                var endIndex = after.endIndex
                for end in endMarkers {
                    if let r = after.range(of: end, options: .caseInsensitive), r.lowerBound < endIndex {
                        endIndex = r.lowerBound
                    }
                }
                return String(after[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTimelineLines(_ content: String) -> [ReconstructedTimelineEvent] {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ($0.first?.isNumber == true || $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") || $0.range(of: #"\d"#, options: .regularExpression) != nil) }
        return lines.map { line in
            let cleaned = line.replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression)
            let (date, description) = parseTimelineLine(cleaned)
            return ReconstructedTimelineEvent(date: date, description: description.isEmpty ? cleaned : description, source: "ai")
        }
    }

    private static func parseTimelineLine(_ line: String) -> (Date?, String) {
        let dashChars: [Character] = ["–", "-", ":"]
        for char in dashChars {
            if let i = line.firstIndex(of: char), i != line.startIndex {
                let before = String(line[..<i]).trimmingCharacters(in: .whitespaces)
                let suffix = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                if !before.isEmpty, !suffix.isEmpty, let date = parseDate(before) {
                    return (date, suffix)
                }
            }
        }
        return (nil, line)
    }

    private static let dateFormats = ["MMM d", "MMMM d", "d MMM", "d MMMM", "MMM d, yyyy", "MMMM d, yyyy", "yyyy-MM-dd"]

    private static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            let f = DateFormatter()
            f.dateFormat = format
            f.timeZone = TimeZone.current
            f.locale = locale
            if let date = f.date(from: trimmed) { return date }
        }
        let short = DateFormatter()
        short.dateStyle = .short
        short.timeStyle = .none
        short.isLenient = true
        return short.date(from: trimmed)
    }
}

// MARK: - Engine

/// Reconstructs the case timeline from messages and evidence analysis using the AI. Returns chronological events with optional dates and source.
final class TimelineReconstructionEngine {

    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    /// Builds a chronological timeline from conversation messages and evidence summaries. Uses the AI to extract key events and dates.
    func buildTimeline(
        messages: [Message],
        evidence: [EvidenceAnalysis]
    ) async throws -> [ReconstructedTimelineEvent] {
        let messageText = messages.map { $0.content }.joined(separator: "\n")
        let evidenceText = evidence.map { $0.summary }.joined(separator: "\n")

        let prompt = """
        Analyze the following case information and reconstruct a chronological timeline.

        Messages:
        \(messageText.isEmpty ? "(No messages yet.)" : messageText)

        Evidence summaries:
        \(evidenceText.isEmpty ? "(No evidence summaries yet.)" : evidenceText)

        Extract key events with dates if possible. List one event per line. Use format: "Date – description" or "description" when no date is known.
        """

        let chatMessage = ChatMessage(sender: .user, text: prompt)
        let (response, _, _) = try await aiEngine.chat(messages: [chatMessage])
        return TimelineParser.parse(response)
    }
}
