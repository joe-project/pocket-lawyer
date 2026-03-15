import Foundation
import Combine

class CaseManager: ObservableObject {

    @Published var cases: [Case] = []

    func createCase(title: String, description: String) {
        let newCase = Case(
            id: UUID(),
            title: title,
            description: description,
            createdAt: Date()
        )
        cases.append(newCase)
    }
}
