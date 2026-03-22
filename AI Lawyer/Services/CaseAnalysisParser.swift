import Foundation

enum CaseAnalysisParser {

    private static let sectionHeaders = [
        "CASE SUMMARY",
        "POTENTIAL CLAIMS",
        "ESTIMATED DAMAGES",
        "EVIDENCE NEEDED",
        "TIMELINE OF EVENTS",
        "NEXT STEPS",
        "DOCUMENTS TO PREPARE",
        "WHERE TO FILE"
    ]

    /// Parses AI response text into a structured CaseAnalysis using the standard section headings.
    static func parse(_ responseText: String) -> CaseAnalysis {
        let text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return CaseAnalysis(
            summary: extractSectionContent(text, header: "CASE SUMMARY"),
            claims: extractListSection(text, header: "POTENTIAL CLAIMS"),
            estimatedDamages: extractSectionContent(text, header: "ESTIMATED DAMAGES"),
            evidenceNeeded: extractListSection(text, header: "EVIDENCE NEEDED"),
            timeline: extractTimelineSection(text),
            nextSteps: extractListSection(text, header: "NEXT STEPS"),
            documents: extractListSection(text, header: "DOCUMENTS TO PREPARE"),
            filingLocations: extractListSection(text, header: "WHERE TO FILE")
        )
    }

    private static func extractSectionContent(_ text: String, header: String) -> String {
        let content = sectionContent(text, after: header)
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func extractListSection(_ text: String, header: String) -> [String] {
        let content = sectionContent(text, after: header)
        return contentToLines(content)
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

    private static func extractTimelineSection(_ text: String) -> [CaseTimelineEvent] {
        let content = sectionContent(text, after: "TIMELINE OF EVENTS")
        return parseTimelineLines(content)
    }

    /// Parses timeline lines (e.g. "Jan 3 – landlord threatened eviction") into CaseTimelineEvent objects. Shared for reuse.
    static func parseTimelineLines(_ content: String) -> [CaseTimelineEvent] {
        let lines = contentToLines(content)
        return lines.map { line -> CaseTimelineEvent in
            let (date, description) = parseTimelineLine(line)
            return CaseTimelineEvent(id: UUID(), date: date, description: description)
        }
    }

    /// Splits a line on " – " or " - " and parses the leading part as a date if possible (e.g. "Jan 3", "January 15"). Returns (date, description).
    private static func parseTimelineLine(_ line: String) -> (Date?, String) {
        let dashChars: [Character] = ["–", "-"]
        var dashIdx: String.Index?
        for char in dashChars {
            if let i = line.firstIndex(of: char), i != line.startIndex {
                let before = line[..<i].trimmingCharacters(in: .whitespaces)
                if !before.isEmpty {
                    dashIdx = i
                    break
                }
            }
        }
        guard let idx = dashIdx else { return (nil, line) }
        let prefix = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
        let suffix = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        guard let date = parseTimelineDate(prefix) else { return (nil, line) }
        return (date, suffix)
    }

    private static let timelineDateFormats = ["MMM d", "MMMM d", "d MMM", "d MMMM", "MMM d, yyyy", "MMMM d, yyyy"]

    private static func parseTimelineDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        for format in timelineDateFormats {
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
