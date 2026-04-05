import XCTest
@testable import AI_Lawyer

final class DocumentAutofillServiceTests: XCTestCase {
    func testMapsCaseNumberAndPartiesFromCaseContext() {
        let service = DocumentAutofillService()
        let processed = ProcessedDocument(
            originalFileName: "complaint.pdf",
            originalFileType: .pdf,
            kind: .fillablePDF,
            title: "Complaint",
            pageCount: 1,
            extractedText: "",
            fields: [
                ParsedDocumentField(name: "case_number", label: "Case Number", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil),
                ParsedDocumentField(name: "plaintiff", label: "Plaintiff", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil),
                ParsedDocumentField(name: "defendant", label: "Defendant", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil)
            ]
        )

        let folder = CaseFolder(title: "Jones vs. Smith", category: .inProgress, courtCaseNumber: "24-CV-0091")
        let state = CaseState(
            caseId: folder.id,
            title: folder.title,
            participants: [],
            messages: [],
            evidence: [],
            timelineEvents: [],
            claims: [],
            documents: [],
            emailDrafts: [],
            deadlines: [],
            litigationStrategy: nil,
            analysis: nil,
            confidence: nil,
            evidenceAlerts: [],
            legalArguments: []
        )

        let draft = service.prepareDraft(for: processed, caseState: state, caseFolder: folder)

        XCTAssertEqual(draft.fields.first(where: { $0.label == "Case Number" })?.value, "24-CV-0091")
        XCTAssertEqual(draft.fields.first(where: { $0.label == "Plaintiff" })?.value, "Jones")
        XCTAssertEqual(draft.fields.first(where: { $0.label == "Defendant" })?.value, "Smith")
    }

    func testMarksMissingFieldsInsteadOfInventingValues() {
        let service = DocumentAutofillService()
        let processed = ProcessedDocument(
            originalFileName: "form.pdf",
            originalFileType: .pdf,
            kind: .flatPDF,
            title: "Form",
            pageCount: 1,
            extractedText: "",
            fields: [
                ParsedDocumentField(name: "email", label: "Email Address", pageIndex: 0, existingValue: nil, pdfBounds: nil, normalizedBounds: nil)
            ]
        )

        let folder = CaseFolder(title: "General Law Questions", category: .inProgress)
        let state = CaseState(
            caseId: folder.id,
            title: folder.title,
            participants: [],
            messages: [],
            evidence: [],
            timelineEvents: [],
            claims: [],
            documents: [],
            emailDrafts: [],
            deadlines: [],
            litigationStrategy: nil,
            analysis: nil,
            confidence: nil,
            evidenceAlerts: [],
            legalArguments: []
        )

        let draft = service.prepareDraft(for: processed, caseState: state, caseFolder: folder)
        XCTAssertEqual(draft.fields.first?.confidence, .missing)
        XCTAssertEqual(draft.missingFieldLabels, ["Email Address"])
    }

    func testCompletedFileNameIsPredictable() {
        let writer = CompletedDocumentWriter()
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: "2026-04-05T12:00:00Z")!
        XCTAssertEqual(
            writer.completedFileName(for: "JudicialCouncilForm.pdf", date: date),
            "JudicialCouncilForm_completed_2026-04-05.pdf"
        )
    }
}
