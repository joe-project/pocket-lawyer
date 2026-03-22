import Foundation

/// Parses AI response text into a LitigationStrategy using the standard section headings:
/// LEGAL THEORIES, STRENGTHS, WEAKNESSES, EVIDENCE GAPS, OPPOSING ARGUMENTS, SETTLEMENT RANGE, LITIGATION PLAN.
enum LitigationStrategyParser {
    private static let sectionHeaders = [
        "LEGAL THEORIES",
        "STRENGTHS",
        "WEAKNESSES",
        "EVIDENCE GAPS",
        "OPPOSING ARGUMENTS",
        "SETTLEMENT RANGE",
        "LITIGATION PLAN"
    ]

    /// Converts the AI response into a LitigationStrategy by extracting each section.
    static func parse(_ responseText: String) -> LitigationStrategy {
        let text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return LitigationStrategy(
            legalTheories: extractListSection(text, header: "LEGAL THEORIES"),
            strengths: extractListSection(text, header: "STRENGTHS"),
            weaknesses: extractListSection(text, header: "WEAKNESSES"),
            evidenceGaps: extractListSection(text, header: "EVIDENCE GAPS"),
            opposingArguments: extractListSection(text, header: "OPPOSING ARGUMENTS"),
            settlementRange: extractOptionalSection(text, header: "SETTLEMENT RANGE"),
            litigationPlan: extractListSection(text, header: "LITIGATION PLAN")
        )
    }

    private static func extractListSection(_ text: String, header: String) -> [String] {
        let content = sectionContent(text, after: header)
        return contentToLines(content)
    }

    private static func extractOptionalSection(_ text: String, header: String) -> String? {
        let content = sectionContent(text, after: header).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
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

    private static func contentToLines(_ content: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        return lines
            .map { stripBulletOrNumber($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func stripBulletOrNumber(_ line: String) -> String {
        var s = line
        let bulletChars = CharacterSet(charactersIn: "•*-–—")
        if let first = s.unicodeScalars.first, bulletChars.contains(first) {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if let firstChar = s.first, firstChar.isNumber {
            if let idx = s.firstIndex(where: { $0 == "." || $0 == ")" }) {
                s = String(s[s.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return s
    }
}
