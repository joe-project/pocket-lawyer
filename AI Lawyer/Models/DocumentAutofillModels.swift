import Foundation
import CoreGraphics

enum ImportedDocumentKind: String {
    case fillablePDF
    case flatPDF
    case scannedPDF
    case image
}

enum AutofillValueConfidence: String {
    case exactMatch
    case inferredFromCase
    case missing
}

struct ParsedDocumentField: Identifiable {
    let id = UUID()
    var name: String
    var label: String
    var pageIndex: Int
    var existingValue: String?
    var pdfBounds: CGRect?
    var normalizedBounds: CGRect?
}

struct ProcessedDocument {
    var originalFileName: String
    var originalFileType: CaseFileType
    var kind: ImportedDocumentKind
    var title: String
    var pageCount: Int
    var extractedText: String
    var fields: [ParsedDocumentField]
}

struct AutofillDraftField: Identifiable {
    let id = UUID()
    var fieldName: String
    var label: String
    var pageIndex: Int
    var value: String
    var confidence: AutofillValueConfidence
    var source: String
    var pdfBounds: CGRect?
    var normalizedBounds: CGRect?
}

struct DocumentAutofillDraft {
    var title: String
    var fields: [AutofillDraftField]
    var summary: String
    var missingFieldLabels: [String]
}
