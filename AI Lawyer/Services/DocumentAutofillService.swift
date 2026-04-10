import Foundation

final class DocumentAutofillService {
    func prepareDraft(
        for processed: ProcessedDocument,
        caseState: CaseState,
        caseFolder: CaseFolder?
    ) -> DocumentAutofillDraft {
        let context = CaseAutofillContext(caseState: caseState, caseFolder: caseFolder)
        let candidateFields = processed.fields.isEmpty
            ? fallbackFields(for: processed)
            : processed.fields

        let filledFields = candidateFields.map { field in
            let match = matchValue(for: field.label, context: context)
            return AutofillDraftField(
                fieldName: field.name,
                label: field.label,
                pageIndex: field.pageIndex,
                value: match.value,
                confidence: match.confidence,
                source: match.source,
                pdfBounds: field.pdfBounds,
                normalizedBounds: field.normalizedBounds
            )
        }

        let missing = filledFields
            .filter { $0.confidence == .missing }
            .map(\.label)

        let summary = buildSummary(processed: processed, fields: filledFields, missing: missing)

        return DocumentAutofillDraft(
            title: processed.title,
            fields: filledFields,
            summary: summary,
            missingFieldLabels: missing
        )
    }

    private func fallbackFields(for processed: ProcessedDocument) -> [ParsedDocumentField] {
        [
            ParsedDocumentField(name: "case_number", label: "Case Number", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil),
            ParsedDocumentField(name: "court_name", label: "Court Name", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil),
            ParsedDocumentField(name: "your_name", label: "Your Name", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil),
            ParsedDocumentField(name: "incident_summary", label: "Incident Summary", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil)
        ]
    }

    private func buildSummary(processed: ProcessedDocument, fields: [AutofillDraftField], missing: [String]) -> String {
        let matchedCount = fields.filter { $0.confidence != .missing }.count
        if missing.isEmpty {
            return "Prepared \(matchedCount) field values from the current case context for \(processed.title)."
        }
        return "Prepared \(matchedCount) field values for \(processed.title). Review \(missing.count) missing items before exporting."
    }

    private func matchValue(for label: String, context: CaseAutofillContext) -> (value: String, confidence: AutofillValueConfidence, source: String) {
        let lower = label.lowercased()

        func exact(_ value: String?, _ source: String) -> (String, AutofillValueConfidence, String) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? ("", .missing, "Needs review") : (trimmed, .exactMatch, source)
        }

        func inferred(_ value: String?, _ source: String) -> (String, AutofillValueConfidence, String) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? ("", .missing, "Needs review") : (trimmed, .inferredFromCase, source)
        }

        if lower.contains("case number") || lower.contains("case no") || lower.contains("case #") {
            return exact(context.caseNumber, "Court case number")
        }
        if lower.contains("court") {
            return inferred(context.courtName, "Detected from chat or case notes")
        }
        if lower.contains("plaintiff") || lower.contains("petitioner") || lower.contains("claimant") || lower.contains("applicant") {
            return inferred(context.primaryParty, "Case title")
        }
        if lower.contains("defendant") || lower.contains("respondent") || lower.contains("other party") {
            return inferred(context.secondaryParty, "Case title")
        }
        if lower.contains("tenant") || lower == "your name" || lower.contains("full name") || lower == "name" {
            return inferred(context.primaryParty, "Case title or chat context")
        }
        if lower.contains("landlord") {
            return inferred(context.secondaryParty, "Case title or chat context")
        }
        if lower.contains("address") {
            return inferred(context.address, "Detected from messages or documents")
        }
        if lower.contains("phone") || lower.contains("telephone") {
            return inferred(context.phone, "Detected from messages or documents")
        }
        if lower.contains("email") {
            return inferred(context.email, "Detected from messages or documents")
        }
        if lower.contains("incident") || lower.contains("statement") || lower.contains("facts") || lower.contains("describe") || lower.contains("summary") {
            return inferred(context.incidentSummary, "Conversation and case summary")
        }
        if lower.contains("claim") || lower.contains("reason") {
            return inferred(context.claimSummary, "Case analysis")
        }
        if lower.contains("date") {
            return inferred(context.incidentDate, "Timeline or chat")
        }

        return ("", .missing, "Needs review")
    }
}

private struct CaseAutofillContext {
    let caseNumber: String?
    let courtName: String?
    let primaryParty: String?
    let secondaryParty: String?
    let address: String?
    let phone: String?
    let email: String?
    let incidentSummary: String?
    let claimSummary: String?
    let incidentDate: String?

    init(caseState: CaseState, caseFolder: CaseFolder?) {
        let messagesText = caseState.messages.map(\.content).joined(separator: "\n")
        let documentText = caseState.documents.compactMap(\.content).joined(separator: "\n")
        let corpus = [messagesText, documentText].joined(separator: "\n")

        let parties = Self.splitParties(from: caseFolder?.title ?? caseState.title)
        self.caseNumber = caseFolder?.courtCaseNumber
        self.courtName = Self.firstMatch(in: corpus, pattern: #"\b(?:[A-Z][A-Za-z]+ )*(?:Court|COURT)(?: of [A-Z][A-Za-z ]+)?\b"#)
        self.primaryParty = parties.primary
        self.secondaryParty = parties.secondary
        self.address = Self.firstMatch(in: corpus, pattern: #"\d{1,6}\s+[A-Za-z0-9.\- ]+\s(?:Street|St|Avenue|Ave|Road|Rd|Lane|Ln|Drive|Dr|Boulevard|Blvd|Court|Ct|Way)\b(?:,?\s+[A-Za-z.\- ]+)?(?:,?\s+[A-Z]{2}\s+\d{5})?"#)
        self.phone = Self.firstMatch(in: corpus, pattern: #"(?:\+1\s*)?(?:\(\d{3}\)|\d{3})[-.\s]?\d{3}[-.\s]?\d{4}"#)
        self.email = Self.firstMatch(in: corpus, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive])
        self.incidentSummary = Self.incidentSummary(from: caseState)
        self.claimSummary = caseState.analysis?.claims.joined(separator: ", ")
        if let firstTimelineDate = caseState.analysis?.timeline.first?.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            self.incidentDate = formatter.string(from: firstTimelineDate)
        } else {
            self.incidentDate = Self.firstMatch(in: corpus, pattern: #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},\s+\d{4}\b"#)
        }
    }

    private static func splitParties(from title: String) -> (primary: String?, secondary: String?) {
        let normalized = title
            .replacingOccurrences(of: "(Example Case)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let separators = [" vs. ", " vs ", " v. ", " v "]
        for separator in separators where normalized.localizedCaseInsensitiveContains(separator) {
            let components = normalized.components(separatedBy: separator)
            if components.count >= 2 {
                let primary = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let secondary = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return (primary.isEmpty ? nil : primary, secondary.isEmpty ? nil : secondary)
            }
        }
        return (normalized.isEmpty ? nil : normalized, nil)
    }

    private static func incidentSummary(from caseState: CaseState) -> String? {
        let firstUserMessages = caseState.messages
            .filter { $0.role == "user" }
            .prefix(3)
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !firstUserMessages.isEmpty {
            return firstUserMessages.joined(separator: " ")
        }

        return caseState.analysis?.summary
    }

    private static func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
