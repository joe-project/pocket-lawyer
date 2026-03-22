import Foundation

/// Parses AI response text into a CaseConfidence using the section headings:
/// CLAIM STRENGTH, EVIDENCE STRENGTH, SETTLEMENT PROBABILITY, LITIGATION RISK.
enum CaseConfidenceParser {
    private static let sectionHeaders = [
        "CLAIM STRENGTH",
        "EVIDENCE STRENGTH",
        "SETTLEMENT PROBABILITY",
        "LITIGATION RISK"
    ]

    /// Converts the AI response into a CaseConfidence by extracting each section.
    static func parse(_ responseText: String) -> CaseConfidence {
        let text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return CaseConfidence(
            claimStrength: parseClaimStrength(text),
            evidenceStrength: extractSingleLine(text, header: "EVIDENCE STRENGTH"),
            settlementProbability: extractSingleLine(text, header: "SETTLEMENT PROBABILITY"),
            litigationRisk: extractSingleLine(text, header: "LITIGATION RISK")
        )
    }

    private static func parseClaimStrength(_ text: String) -> Int {
        let content = sectionContent(text, after: "CLAIM STRENGTH").trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = content.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? content
        let value = firstNumber(in: firstLine)
        return (0...100).contains(value) ? value : 50
    }

    /// Extracts the first integer (e.g. 75 from "75%" or "50-60") from the string; returns 50 if none found.
    private static func firstNumber(in string: String) -> Int {
        var digits: [Character] = []
        for c in string {
            if c.isNumber {
                digits.append(c)
            } else if !digits.isEmpty {
                break
            }
        }
        guard let value = Int(String(digits)) else { return 50 }
        return value
    }

    private static func extractSingleLine(_ text: String, header: String) -> String {
        let content = sectionContent(text, after: header).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = content.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? content
        return firstLine.isEmpty ? "—" : firstLine
    }

    private static func sectionContent(_ text: String, after header: String) -> String {
        guard let range = text.range(of: header, options: [.caseInsensitive]) else { return "" }
        let afterHeader = String(text[range.upperBound...])
        var endIndex = afterHeader.endIndex
        for next in sectionHeaders {
            guard next.uppercased() != header.uppercased(),
                  let nextRange = afterHeader.range(of: next, options: [.caseInsensitive]) else { continue }
            if nextRange.lowerBound < endIndex {
                endIndex = nextRange.lowerBound
            }
        }
        return String(afterHeader[..<endIndex])
    }
}
