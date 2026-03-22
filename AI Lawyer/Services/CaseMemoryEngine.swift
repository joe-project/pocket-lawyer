import Foundation

// MARK: - Model

/// Persistent structured memory for a case so the AI does not need to reread the full conversation.
struct CaseMemory: Codable, Equatable {
    var people: [String]
    var events: [String]
    var evidence: [String]
    var claims: [String]
    var damagesEstimate: String?

    init(
        people: [String] = [],
        events: [String] = [],
        evidence: [String] = [],
        claims: [String] = [],
        damagesEstimate: String? = nil
    ) {
        self.people = people
        self.events = events
        self.evidence = evidence
        self.claims = claims
        self.damagesEstimate = damagesEstimate
    }
}

// MARK: - Parser

/// Parses AI response into CaseMemory using section headers PEOPLE, EVENTS, EVIDENCE, CLAIMS, DAMAGES.
enum CaseMemoryParser {

    private static let sectionMarkers = ["PEOPLE", "EVENTS", "EVIDENCE", "CLAIMS", "DAMAGES"]

    /// Parses the raw AI response into CaseMemory. Expects section-based text with the markers above.
    static func parse(_ response: String) -> CaseMemory {
        let trimmed = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let people = listFromSection(trimmed, marker: "PEOPLE")
        let events = listFromSection(trimmed, marker: "EVENTS")
        let evidence = listFromSection(trimmed, marker: "EVIDENCE")
        let claims = listFromSection(trimmed, marker: "CLAIMS")
        let damages = singleLineFromSection(trimmed, marker: "DAMAGES")

        return CaseMemory(
            people: people,
            events: events,
            evidence: evidence,
            claims: claims,
            damagesEstimate: damages.isEmpty ? nil : damages
        )
    }

    private static func listFromSection(_ text: String, marker: String) -> [String] {
        guard let content = contentAfterSection(text, marker: marker) else { return [] }
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
                if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
                if line.range(of: "^[0-9]+\\.\\s*", options: .regularExpression) != nil {
                    return line.replacingOccurrences(of: "^[0-9]+\\.\\s*", with: "", options: .regularExpression)
                }
                return line
            }
    }

    private static func singleLineFromSection(_ text: String, marker: String) -> String {
        guard let content = contentAfterSection(text, marker: marker) else { return "" }
        return content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces)
            ?? ""
    }

    private static func contentAfterSection(_ text: String, marker: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let upperMarker = marker.uppercased()
        var inSection = false
        var result: [String] = []

        for line in lines {
            let upper = line.uppercased().trimmingCharacters(in: .whitespaces)
            if upper == upperMarker || upper.hasPrefix("\(upperMarker):") || upper.hasPrefix("\(upperMarker) ") {
                inSection = true
                let afterMarker = line.range(of: upperMarker, options: .caseInsensitive).map { range in
                    String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                        .trimmingCharacters(in: .whitespaces)
                } ?? ""
                if !afterMarker.isEmpty { result.append(afterMarker) }
                continue
            }
            if inSection {
                if sectionMarkers.contains(where: { upper == $0 || upper.hasPrefix("\($0):") || upper.hasPrefix("\($0) ") }) {
                    break
                }
                result.append(line)
            }
        }
        return result.isEmpty ? nil : result.joined(separator: "\n")
    }
}

// MARK: - Engine

/// Maintains a persistent structured memory of the case so the AI does not need to reread the full conversation.
final class CaseMemoryEngine {

    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    /// Formats current memory for the prompt.
    private func formatMemory(_ memory: CaseMemory) -> String {
        var parts: [String] = []
        if !memory.people.isEmpty {
            parts.append("PEOPLE:\n" + memory.people.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !memory.events.isEmpty {
            parts.append("EVENTS:\n" + memory.events.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !memory.evidence.isEmpty {
            parts.append("EVIDENCE:\n" + memory.evidence.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !memory.claims.isEmpty {
            parts.append("CLAIMS:\n" + memory.claims.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let d = memory.damagesEstimate, !d.isEmpty {
            parts.append("DAMAGES: \(d)")
        }
        return parts.isEmpty ? "(none yet)" : parts.joined(separator: "\n\n")
    }

    /// Updates the case memory with new information using the AI. Returns the updated CaseMemory.
    func updateMemory(memory: CaseMemory, newInformation: String) async throws -> CaseMemory {
        let memoryText = formatMemory(memory)
        let prompt = """
        Update the case memory with the new information.

        Current memory:
        \(memoryText)

        New information:
        \(newInformation)

        Update these sections if necessary:
        PEOPLE
        EVENTS
        EVIDENCE
        CLAIMS
        DAMAGES

        Reply with only the updated sections, using exactly these headers (one per line). Under each header list items as bullet points (- item) or a single line for DAMAGES. Do not add commentary.
        """

        let chatMessage = ChatMessage(sender: .user, text: prompt)
        let (response, _, _) = try await aiEngine.chat(messages: [chatMessage])
        return CaseMemoryParser.parse(response)
    }
}
