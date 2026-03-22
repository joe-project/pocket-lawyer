import SwiftUI

/// App root: **ZStack** shell — sidebar overlays from the left (not `HStack`); main content offsets when open.
struct RootContainerView: View {
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @StateObject private var workspace = WorkspaceManager()

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasAcceptedLegalDisclaimer") private var hasAcceptedLegalDisclaimer = false

    @State private var selectedWorkspaceItem: SidebarWorkspaceItem = .activeCase1
    @State private var showAddEvidenceSheet = false
    @State private var isSidebarOpen = true

    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var showFileImporter = false

    private let sidebarWidth: CGFloat = 300

    var body: some View {
        Group {
            if !hasSeenWelcome {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
                    .environmentObject(workspace)
            } else if !hasAcceptedLegalDisclaimer {
                LegalDisclaimerAcceptView(hasAcceptedLegalDisclaimer: $hasAcceptedLegalDisclaimer)
            } else {
                ZStack(alignment: .leading) {
                    Color.black
                        .ignoresSafeArea()

                    Group {
                        VStack(spacing: 0) {
                            MainContentView(
                                selectedWorkspaceItem: $selectedWorkspaceItem,
                                showAddEvidenceSheet: $showAddEvidenceSheet,
                                isSidebarOpen: $isSidebarOpen,
                                chatViewModel: chatViewModel
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea(.keyboard, edges: [])
                            .scrollDismissesKeyboard(.interactively)
                            .background(Color.black)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            ChatInputBar(
                                chatViewModel: chatViewModel,
                                voiceRecorder: voiceRecorder,
                                showFileImporter: $showFileImporter
                            )
                            .background(Color.black)
                        }
                    }
                    .offset(x: isSidebarOpen ? sidebarWidth : 0)
                    .animation(.easeInOut(duration: 0.25), value: isSidebarOpen)

                    if isSidebarOpen {
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: sidebarWidth)
                            Color.black.opacity(0.35)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        isSidebarOpen = false
                                    }
                                }
                        }
                        .ignoresSafeArea()
                        .zIndex(1)
                    }

                    SidebarView(
                        showAddEvidenceSheet: $showAddEvidenceSheet,
                        selectedItem: $selectedWorkspaceItem
                    )
                    .frame(width: sidebarWidth)
                    .background(Color(.systemBackground))
                    .offset(x: isSidebarOpen ? 0 : -sidebarWidth)
                    .animation(.easeInOut(duration: 0.25), value: isSidebarOpen)
                    .ignoresSafeArea(edges: .vertical)
                    .zIndex(2)

                    if !isSidebarOpen {
                        sidebarReopenEdge
                            .zIndex(3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environmentObject(workspace)
            }
        }
        .onOpenURL { url in
            handleInviteURL(url)
        }
    }

    private func handleInviteURL(_ url: URL) {
        guard url.scheme == CaseCollaborationEngine.inviteURLScheme,
              url.host == CaseCollaborationEngine.inviteURLHost,
              url.pathComponents.count >= 2 else { return }
        let token = url.pathComponents[1]
        _ = workspace.applyInvitation(token: token)
    }

    /// ~36pt leading strip when sidebar is hidden (tap or swipe right to open).
    private var sidebarReopenEdge: some View {
        HStack(spacing: 0) {
            VStack {
                Spacer(minLength: 0)
                Capsule()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 6, height: 48)
                Spacer(minLength: 0)
            }
            .frame(width: 36)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSidebarOpen = true
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 16)
                    .onEnded { value in
                        if value.translation.width > 40 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSidebarOpen = true
                            }
                        }
                    }
            )
            Spacer(minLength: 0)
        }
        .allowsHitTesting(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
