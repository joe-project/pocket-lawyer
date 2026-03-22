import Foundation

/// Tracks legal deadlines per case (filing, response due, etc.). Delegates storage to case tree / case folder persistence.
final class LegalDeadlineTracker {

    private weak var caseTreeViewModel: CaseTreeViewModel?

    init(caseTreeViewModel: CaseTreeViewModel) {
        self.caseTreeViewModel = caseTreeViewModel
    }

    /// Returns all deadlines for the given case.
    func deadlines(for caseId: UUID) -> [LegalDeadline] {
        caseTreeViewModel?.deadlines(for: caseId) ?? []
    }

    /// Appends new deadlines to the case (e.g. from evidence analysis or manual entry).
    func addDeadlines(_ newDeadlines: [LegalDeadline], caseId: UUID) {
        caseTreeViewModel?.addDeadlines(newDeadlines, caseId: caseId)
    }
}
