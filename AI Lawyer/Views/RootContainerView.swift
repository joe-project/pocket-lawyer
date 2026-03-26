import SwiftUI
import UIKit

/// `VStack`: fixed `TopBarView` + `ZStack` where only main body slides (not the header). `ChatInputBar` is `safeAreaInset`.
struct RootContainerView: View {
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @EnvironmentObject var workspace: WorkspaceManager

    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasAcceptedLegalDisclaimer") private var hasAcceptedLegalDisclaimer = false

    @State private var selectedWorkspaceItem: SidebarWorkspaceItem = .activeCase1
    @State private var showAddEvidenceSheet = false
    @State private var isSidebarOpen = true
    /// `0` = fully open, `-sidebarWidth` = fully closed (matches drag math).
    @State private var sidebarOffset: CGFloat = 0
    @State private var sidebarDragStartOffset: CGFloat?
    @State private var showHamburgerMenu = false

    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var showFileImporter = false

    private let sidebarWidth: CGFloat = 300
    private let sidebarHandleHitWidth: CGFloat = 44

    var body: some View {
        Group {
            if !hasSeenWelcome {
                WelcomeView(hasSeenWelcome: $hasSeenWelcome)
            } else if !hasAcceptedLegalDisclaimer {
                LegalDisclaimerAcceptView(hasAcceptedLegalDisclaimer: $hasAcceptedLegalDisclaimer)
            } else {
                VStack(spacing: 0) {
                    TopBarView(showHamburgerMenu: $showHamburgerMenu)

                    ZStack(alignment: .leading) {
                        (isDarkMode ? AppColors.darkBackground : AppColors.lightBackground)

                        MainContentView(
                            selectedWorkspaceItem: $selectedWorkspaceItem,
                            showAddEvidenceSheet: $showAddEvidenceSheet,
                            showHamburgerMenu: $showHamburgerMenu,
                            chatViewModel: workspace.chatViewModel
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isDarkMode ? AppColors.darkBackground : AppColors.lightBackground)
                        .ignoresSafeArea(.keyboard, edges: [])
                        .scrollDismissesKeyboard(.interactively)
                        .offset(x: sidebarWidth + sidebarOffset)

                        if sidebarOffset > -sidebarWidth {
                            HStack(spacing: 0) {
                                Color.clear
                                    .frame(width: max(0, sidebarWidth + sidebarOffset))
                                Color.black.opacity(0.35)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                            isSidebarOpen = false
                                            sidebarOffset = -sidebarWidth
                                        }
                                    }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(true)
                            .zIndex(1)
                        }

                        SidebarView(
                            showAddEvidenceSheet: $showAddEvidenceSheet,
                            selectedItem: $selectedWorkspaceItem
                        )
                        .frame(width: sidebarWidth)
                        .offset(x: sidebarOffset)
                        .simultaneousGesture(sidebarCloseDragGesture)
                        .ignoresSafeArea(edges: .vertical)
                        .zIndex(2)

                        Capsule()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 4, height: 40)
                            .position(
                                x: max(16, min(sidebarWidth, sidebarOffset + sidebarWidth - 2)),
                                y: UIScreen.main.bounds.height / 2
                            )
                            .allowsHitTesting(false)
                            .zIndex(10)

                        Color.clear
                            .frame(width: sidebarHandleHitWidth)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .position(
                                x: max(16, min(sidebarWidth, sidebarOffset + sidebarWidth - 2)),
                                y: UIScreen.main.bounds.height / 2
                            )
                            .gesture(sidebarHandleDragGesture)
                            .zIndex(11)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isDarkMode ? AppColors.darkBackground : AppColors.lightBackground)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ChatInputBar(
                        chatViewModel: workspace.chatViewModel,
                        voiceRecorder: voiceRecorder,
                        showFileImporter: $showFileImporter
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .background(Color.clear)
                }
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

    private var sidebarHandleDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if sidebarDragStartOffset == nil {
                    sidebarDragStartOffset = sidebarOffset
                }
                let base = sidebarDragStartOffset!
                let proposed = base + value.translation.width
                sidebarOffset = min(0, max(-sidebarWidth, proposed))
                isSidebarOpen = sidebarOffset > -sidebarWidth / 2
            }
            .onEnded { value in
                sidebarDragStartOffset = nil
                let drag = value.translation.width
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if drag > 80 {
                        isSidebarOpen = true
                        sidebarOffset = 0
                    } else if drag < -80 {
                        isSidebarOpen = false
                        sidebarOffset = -sidebarWidth
                    } else if sidebarOffset > -sidebarWidth / 2 {
                        isSidebarOpen = true
                        sidebarOffset = 0
                    } else {
                        isSidebarOpen = false
                        sidebarOffset = -sidebarWidth
                    }
                }
            }
    }

    private var sidebarCloseDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard sidebarOffset > -sidebarWidth else { return }
                guard value.translation.width < 0 else { return }
                if sidebarDragStartOffset == nil {
                    sidebarDragStartOffset = sidebarOffset
                }
                let base = sidebarDragStartOffset!
                let proposed = base + value.translation.width
                sidebarOffset = min(0, max(-sidebarWidth, proposed))
                isSidebarOpen = sidebarOffset > -sidebarWidth / 2
            }
            .onEnded { value in
                guard sidebarDragStartOffset != nil else { return }
                sidebarDragStartOffset = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if value.translation.width < -60 {
                        isSidebarOpen = false
                        sidebarOffset = -sidebarWidth
                    } else {
                        isSidebarOpen = true
                        sidebarOffset = 0
                    }
                }
            }
    }
}
