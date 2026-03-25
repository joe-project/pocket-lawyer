import SwiftUI

@main
struct AILawyerApp: App {
    @StateObject private var subscriptionViewModel = SubscriptionViewModel()
    @StateObject private var workspace = WorkspaceManager()
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(workspace)
                .environmentObject(workspace.chatViewModel)
                .environmentObject(workspace.conversationManager)
                .environmentObject(workspace.caseManager)
                .environmentObject(subscriptionViewModel)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}
