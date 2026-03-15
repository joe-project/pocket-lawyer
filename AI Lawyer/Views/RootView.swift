import SwiftUI

struct RootView: View {
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasAcceptedLegalDisclaimer") private var hasAcceptedLegalDisclaimer = false

    var body: some View {
        Group {
            if !hasSeenWelcome {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
            } else if !hasAcceptedLegalDisclaimer {
                LegalDisclaimerAcceptView(hasAcceptedLegalDisclaimer: $hasAcceptedLegalDisclaimer)
            } else {
                MainDashboardView()
            }
        }
    }
}
