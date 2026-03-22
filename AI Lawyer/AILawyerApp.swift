import SwiftUI

@main
struct AILawyerApp: App {
    @StateObject private var subscriptionViewModel = SubscriptionViewModel()
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(subscriptionViewModel)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}
