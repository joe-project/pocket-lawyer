import Foundation
import Combine

@MainActor
final class SubscriptionViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var hasFullAccess: Bool = true
}
