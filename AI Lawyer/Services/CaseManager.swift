import Foundation
import Combine

class CaseManager: ObservableObject {

    @Published var cases: [Case] = []

    func createCase(title: String, description: String) {
        let newCase = Case(
            title: title,
            description: description,
            createdAt: Date()
        )
        cases.append(newCase)
    }

    /// Appends timeline events extracted from an AI response to a case.
    func addTimelineEvents(_ events: [CaseTimelineEvent], toCaseId caseId: UUID) {
        guard let index = cases.firstIndex(where: { $0.id == caseId }) else { return }
        cases[index].timelineEvents.append(contentsOf: events)
    }

    /// Ensures a Case exists for the given id and title (e.g. from CaseFolder). Creates one if missing so setAnalysis can run.
    func ensureCaseExists(caseId: UUID, title: String) {
        guard cases.firstIndex(where: { $0.id == caseId }) == nil else { return }
        let newCase = Case(id: caseId, title: title, description: "", createdAt: Date(), timelineEvents: [], analysis: nil)
        cases.append(newCase)
    }

    /// Attaches a parsed CaseAnalysis to the active case so it maintains summary, claims, estimated damages, timeline, evidence, next steps, etc.
    func setAnalysis(_ analysis: CaseAnalysis, forCaseId caseId: UUID) {
        guard let index = cases.firstIndex(where: { $0.id == caseId }) else { return }
        cases[index].analysis = analysis
    }

    /// Returns the case with the given id, if any.
    func getCase(byId caseId: UUID) -> Case? {
        cases.first { $0.id == caseId }
    }
}
