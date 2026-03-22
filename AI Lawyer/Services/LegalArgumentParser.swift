import Foundation

/// Parses AI responses containing structured legal arguments (IRAC) into `LegalArgument` objects.
/// Supports both JSON array output and section-based text (CLAIM, LEGAL RULE, FACTS, EVIDENCE, CONCLUSION).
enum LegalArgumentParser {

    private static let sectionMarkers = ["CLAIM", "LEGAL RULE", "FACTS", "EVIDENCE", "CONCLUSION"]

    /// Parses the raw AI response into an array of `LegalArgument`. Tries JSON first, then section-based extraction.
    static func parse(_ response: String) -> [LegalArgument] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = parseJSON(normalized), !parsed.isEmpty {
            return parsed
        }
        return parseSections(normalized)
    }

    // MARK: - JSON

    private static func parseJSON(_ text: String) -> [LegalArgument]? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            let dtos = try JSONDecoder().decode([LegalArgumentDTO].self, from: data)
            let result = dtos.compactMap { $0.toLegalArgument() }
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    // MARK: - Section-based (CLAIM / LEGAL RULE / FACTS / EVIDENCE / CONCLUSION)

    private static func parseSections(_ text: String) -> [LegalArgument] {
        // Split into argument blocks: each block starts with CLAIM (on its own line or at start of line).
        let blocks = splitIntoBlocks(text)
        return blocks.compactMap { parseOneArgument(block: $0) }
    }

    /// Splits text by "CLAIM" section starts so we get one block per argument.
    private static func splitIntoBlocks(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [String] = []
        var current: [String] = []
        var foundFirstClaim = false

        for line in lines {
            let upper = line.uppercased().trimmingCharacters(in: .whitespaces)
            let isClaimLine = upper == "CLAIM" || upper.hasPrefix("CLAIM ") || upper == "CLAIM:"

            if isClaimLine && foundFirstClaim && !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current = []
            }
            if isClaimLine { foundFirstClaim = true }
            current.append(line)
        }
        if !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }
        return blocks.isEmpty && foundFirstClaim ? [text] : blocks
    }

    private static func parseOneArgument(block: String) -> LegalArgument? {
        let claim = extractSectionContent(block, marker: "CLAIM")
        let legalRule = extractSectionContent(block, marker: "LEGAL RULE")
        let facts = extractSectionContent(block, marker: "FACTS")
        let evidenceText = extractSectionContent(block, marker: "EVIDENCE")
        let conclusion = extractSectionContent(block, marker: "CONCLUSION")

        guard let claim = claim, !claim.isEmpty else { return nil }
        return LegalArgument(
            claim: claim,
            legalRule: legalRule ?? "",
            facts: facts ?? "",
            evidence: parseEvidenceList(evidenceText ?? ""),
            conclusion: conclusion ?? ""
        )
    }

    /// Returns content after the first occurrence of the section marker (line that equals or starts with marker), until the next section or end.
    private static func extractSectionContent(_ block: String, marker: String) -> String? {
        let lines = block.components(separatedBy: .newlines)
        let markerUpper = marker.uppercased()
        var collecting = false
        var content: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            let isThisSection = upper == markerUpper || upper.hasPrefix(markerUpper + " ") || upper.hasPrefix(markerUpper + ":")

            if isThisSection {
                if collecting { break }
                collecting = true
                let afterMarker = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if afterMarker.hasPrefix(":") {
                    content.append(String(afterMarker.dropFirst()).trimmingCharacters(in: .whitespaces))
                } else if !afterMarker.isEmpty {
                    content.append(afterMarker)
                }
                continue
            }
            if collecting {
                content.append(line)
            }
        }
        let result = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Turns EVIDENCE section text into an array (bullet lines or numbered lines).
    private static func parseEvidenceList(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") {
                return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.first?.isNumber == true {
                if let dot = trimmed.firstIndex(of: "."), dot != trimmed.startIndex {
                    return String(trimmed[trimmed.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                }
                if let paren = trimmed.firstIndex(of: ")"), paren != trimmed.startIndex {
                    return String(trimmed[trimmed.index(after: paren)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            return trimmed
        }.filter { !$0.isEmpty }
    }
}

// MARK: - JSON DTO

private struct LegalArgumentDTO: Decodable {
    let claim: String?
    let legalRule: String?
    let facts: String?
    let evidence: [String]?
    let conclusion: String?

    func toLegalArgument() -> LegalArgument? {
        guard let claim = claim?.trimmingCharacters(in: .whitespacesAndNewlines), !claim.isEmpty,
              let legalRule = legalRule?.trimmingCharacters(in: .whitespacesAndNewlines),
              let facts = facts?.trimmingCharacters(in: .whitespacesAndNewlines),
              let conclusion = conclusion?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return LegalArgument(
            claim: claim,
            legalRule: legalRule,
            facts: facts,
            evidence: evidence ?? [],
            conclusion: conclusion
        )
    }
}
