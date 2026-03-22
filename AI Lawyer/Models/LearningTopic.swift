import Foundation

struct LearningTopic: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
}

enum LearningCategory: String, CaseIterable, Identifiable {
    case realEstateLaw = "Real Estate Law"
    case criminalLaw = "Criminal Law"
    case insuranceLaw = "Insurance Law"
    case trustLaw = "Trust Law"
    case lawsuits = "Lawsuits"
    case creditRepair = "Credit Repair"
    case contracts = "Contracts"
    case civilProcedure = "Civil Procedure"
    case patents = "Patents"
    case businessLaw = "Business Law"

    var id: String { rawValue }
}
