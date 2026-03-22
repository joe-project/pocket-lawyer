import SwiftUI
import UIKit
import UniformTypeIdentifiers

private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Main workspace (top bar + scroll content). Sidebar is inline; `ChatInputBar` is a bottom `safeAreaInset` in `RootContainerView`.
///
/// Memberwise initializer parameter order follows stored properties: `selectedWorkspaceItem`, `showAddEvidenceSheet`, `isSidebarOpen`, `chatViewModel` (`isSidebarOpen` before `chatViewModel`).
struct MainContentView: View {
    @Binding var selectedWorkspaceItem: SidebarWorkspaceItem
    @Binding var showAddEvidenceSheet: Bool
    @Binding var isSidebarOpen: Bool

    @ObservedObject var chatViewModel: ChatViewModel

    @EnvironmentObject var workspace: WorkspaceManager
    @StateObject private var learningViewModel = LearningViewModel()
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var showHamburgerMenu = false
    @State private var showLearning = false
    @State private var showLegalDisclaimer = false
    @State private var showPrivacyPolicy = false
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("onboarding_shouldOpenFileImporter") private var onboardingShouldOpenFileImporter = false

    // Contextual monetization (Pocket Lawyer Pro) — shown once per session/user.
    @State private var showProTrialModal = false
    @State private var contextualAIInteractionCount = 0
    @State private var contextualAIInteractionTrigger = Int.random(in: 3...5)
    @AppStorage("contextual_pro_modal_not_now") private var contextualProModalNotNow = false
    @AppStorage("contextual_pro_modal_prompt_shown") private var contextualProModalPromptShown = false

    private var caseTreeViewModel: CaseTreeViewModel { workspace.caseTreeViewModel }
    private var conversationManager: ConversationManager { workspace.conversationManager }
    private var caseManager: CaseManager { workspace.caseManager }
    private var panelBackground: Color { isDarkMode ? .black : Color(white: 0.95) }
    private var primaryTextColor: Color { isDarkMode ? .white : .black }
    private var secondaryTextColor: Color { isDarkMode ? .white.opacity(0.65) : .black.opacity(0.6) }

    private func shouldShowProModal() -> Bool {
        guard subscriptionViewModel.hasFullAccess == false else { return false }
        guard contextualProModalPromptShown == false else { return false }
        guard contextualProModalNotNow == false else { return false }
        return true
    }

    private func presentProModal() {
        guard shouldShowProModal() else { return }
        contextualProModalPromptShown = true
        showProTrialModal = true
    }

    private func dismissProModalNotNow() {
        contextualProModalNotNow = true
        showProTrialModal = false
    }

    private func startFreeTrial() {
        // Placeholder implementation: flip local access in this demo project.
        subscriptionViewModel.hasFullAccess = true
        showProTrialModal = false
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            WorkspacePromptView(selectedItem: selectedWorkspaceItem, isDarkMode: isDarkMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
        .overlay(alignment: .bottomLeading) {
            ThemeModeToggleButton()
                .padding(.leading, 16)
                .padding(.bottom, 90)
                .zIndex(5)
        }
        .sheet(isPresented: $showAddEvidenceSheet) {
            AddEvidenceView()
        }
        .onAppear {
            chatViewModel.conversationManager = conversationManager
            chatViewModel.caseManager = caseManager
            chatViewModel.selectedCaseId = caseTreeViewModel.selectedCase?.id
            chatViewModel.selectedSubfolder = caseTreeViewModel.selectedSubfolder
            chatViewModel.selectedFileId = caseTreeViewModel.selectedFileId
            conversationManager.caseManager = caseManager
            conversationManager.caseTreeViewModel = caseTreeViewModel
            conversationManager.onCaseAnalysisUpdated = { caseId, analysis in
                if caseId == caseTreeViewModel.selectedCase?.id {
                    chatViewModel.latestCaseAnalysis = analysis
                }
                Task { await workspace.considerStrategyUpdate(caseId: caseId) }
            }
            conversationManager.legalResearchForCase = { caseId in
                await workspace.legalResearchAppendix(for: caseId)
            }

            // Onboarding option: open add-evidence once.
            if onboardingShouldOpenFileImporter {
                showAddEvidenceSheet = true
                onboardingShouldOpenFileImporter = false
            }
        }
        .onChange(of: caseTreeViewModel.selectedCase?.id) { _, newId in
            chatViewModel.selectedCaseId = newId
            if let id = newId, let c = caseManager.getCase(byId: id) {
                chatViewModel.latestCaseAnalysis = c.analysis
            } else {
                chatViewModel.latestCaseAnalysis = nil
            }
        }
        .onChange(of: caseTreeViewModel.selectedSubfolder) { _, newSubfolder in
            chatViewModel.selectedSubfolder = newSubfolder
        }
        .onChange(of: caseTreeViewModel.selectedFileId) { _, newFileId in
            chatViewModel.selectedFileId = newFileId
        }
        .sheet(isPresented: $showHamburgerMenu) {
            HamburgerMenuView(
                showLegalDisclaimer: $showLegalDisclaimer,
                showPrivacyPolicy: $showPrivacyPolicy
            )
        }
        .sheet(isPresented: $showLearning) {
            NavigationView {
                LearningView().environmentObject(learningViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLearning = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLegalDisclaimer) {
            NavigationView {
                LegalDisclaimerView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLegalDisclaimer = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationView {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPrivacyPolicy = false }
                        }
                    }
            }
        }

        // Contextual monetization triggers
        .onReceive(NotificationCenter.default.publisher(for: .contextualMonetizationDocumentGenerated)) { _ in
            presentProModal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextualMonetizationExport)) { _ in
            presentProModal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextualMonetizationAIInteraction)) { _ in
            guard shouldShowProModal() else { return }
            contextualAIInteractionCount += 1
            if contextualAIInteractionCount >= contextualAIInteractionTrigger {
                presentProModal()
            }
        }

    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarOpen.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(.white)
                        .padding()
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    AppLogo(size: 28)
                    Text("Pocket Lawyer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                Button(action: { showHamburgerMenu = true }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                        .foregroundColor(primaryTextColor)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
        .background(panelBackground)
    }

    private var brandBackgroundGradient: LinearGradient {
        let top = colorScheme == .dark
            ? Color(red: 28/255, green: 28/255, blue: 30/255)   // #1C1C1E
            : Color(red: 249/255, green: 250/255, blue: 251/255) // #F9FAFB
        let bottom = colorScheme == .dark
            ? Color(red: 18/255, green: 18/255, blue: 20/255) // #121214
            : Color(red: 243/255, green: 244/255, blue: 246/255) // #F3F4F6
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private var selectCasePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text("Select a case")
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text("Choose a case from the list to view the workspace.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(20)
        .luxuryCard()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

enum SidebarWorkspaceItem: String {
    case activeCase1 = "Smith vs Jones"
    case activeCase2 = "Brown vs State"
    case activeCase3 = "Davis vs Miller"
    case trustLaw = "Trust Law"
    case realEstate = "Real Estate"
    case credit = "Credit"
    case civil = "Civil"
    case criminal = "Criminal"
    case traffic = "Traffic"
    case marriageFamily = "Marriage & Family"
}

struct SidebarView: View {
    @Binding var showAddEvidenceSheet: Bool
    @Binding var selectedItem: SidebarWorkspaceItem

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text("Active Cases")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Button {
                        showAddEvidenceSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.primaryAccent)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sidebarItem(SidebarWorkspaceItem.activeCase1)
                    sidebarItem(SidebarWorkspaceItem.activeCase2)
                    sidebarItem(SidebarWorkspaceItem.activeCase3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)

                Divider()
                    .background(Color.white.opacity(0.08))

                Text("LAW")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 10) {
                    sidebarItem(.trustLaw)
                    sidebarItem(.realEstate)
                    sidebarItem(.credit)
                    sidebarItem(.civil)
                    sidebarItem(.criminal)
                    sidebarItem(.traffic)
                    sidebarItem(.marriageFamily)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func sidebarItem(_ item: SidebarWorkspaceItem) -> some View {
        Button {
            selectedItem = item
        } label: {
            SidebarCaseRow(
                title: item.rawValue,
                subtitle: "Questions • Documents • Strategies",
                isSelected: selectedItem == item
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarCaseRow: View {
    let title: String
    let subtitle: String?
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundColor(AppColors.secondaryAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)

                Text(subtitle ?? "Unfiled Draft")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minWidth: 160, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
        )
    }
}

struct AppLogo: View {
    var size: CGFloat = 80

    var body: some View {
        Image("AppLogo")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct AddEvidenceView: View {
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add evidence")
                    .font(.headline)
                Text("Attach files or enter evidence details.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Add Evidence")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WorkspacePromptView: View {
    let selectedItem: SidebarWorkspaceItem
    let isDarkMode: Bool

    private var secondary: Color {
        isDarkMode ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    private var cardBackground: Color {
        isDarkMode ? Color.white.opacity(0.03) : Color.black.opacity(0.04)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(selectedItem.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isDarkMode ? .white : .black)

                if selectedItem == .activeCase3 {
                    davisVsMillerCaseCard
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("• Build a mock case")
                        Text("• Ask a question")
                        Text("• Build a document")
                    }
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineSpacing(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 50 {
                        dismissKeyboard()
                    }
                }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isDarkMode ? Color.black : Color.white)
    }

    private var davisVsMillerCaseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Timeline")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isDarkMode ? .white : .black)

            VStack(alignment: .leading, spacing: 8) {
                Text("• Jan 12 - Contract signed")
                Text("• Feb 3 - Payment missed")
                Text("• Feb 10 - Demand letter sent")
            }
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(.gray)

            Text("Evidence")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isDarkMode ? .white : .black)

            VStack(alignment: .leading, spacing: 8) {
                Text("• Signed agreement.pdf")
                Text("• Email thread screenshot")
                Text("• Payment invoice #1023")
            }
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(.gray)

            Text("Next Actions")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isDarkMode ? .white : .black)

            VStack(alignment: .leading, spacing: 8) {
                Text("• File small claims case")
                Text("• Prepare evidence packet")
                Text("• Send final notice")
            }
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .cornerRadius(12)
    }
}

struct ChatTranscriptView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @EnvironmentObject var caseManager: CaseManager
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @State private var upgradePromptToShow: UpgradePrompt?

    /// Messages for the selected case from ConversationManager (typed, voice, and file messages stored as Message).
    private var displayMessages: [ChatMessage] {
        let caseId = caseTreeViewModel.selectedCase?.id
        return conversationManager.messagesForCase(caseId: caseId).map { msg in
            var text = msg.content
            if !msg.attachmentNames.isEmpty {
                text += "\n(Attachments: \(msg.attachmentNames.joined(separator: ", ")))"
            }
            return ChatMessage(
                id: msg.id,
                sender: msg.role == "user" ? .user : .ai,
                text: text,
                date: msg.timestamp
            )
        }
    }

    /// Analysis for the selected case from CaseManager; dashboard shows this so it stays in sync with stored data.
    private var caseAnalysisForSelectedCase: CaseAnalysis? {
        guard let caseId = caseTreeViewModel.selectedCase?.id else { return nil }
        return caseManager.getCase(byId: caseId)?.analysis
    }

    var body: some View {
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(displayMessages) { message in
                        HStack(alignment: .top) {
                            if message.sender == .user {
                                bubble(for: message)
                                Spacer(minLength: 40)
                            } else {
                                Spacer(minLength: 40)
                                VStack(alignment: .trailing, spacing: 8) {
                                    bubble(for: message)
                                    if message.isDocumentOffer {
                                        documentOfferButton(for: message)
                                    }
                                }
                            }
                        }
                    }

                    if conversationManager.offeringResumeIntake {
                        resumeIntakeButton
                    }

                    if let analysis = caseAnalysisForSelectedCase, let caseId = caseTreeViewModel.selectedCase?.id {
                        CaseDashboardView(
                            analysis: analysis,
                            deadlines: caseTreeViewModel.deadlines(for: caseId)
                        )
                        .padding(.top, 8)
                    }
                }
                .padding()
            }
        }
        .sheet(item: $upgradePromptToShow) { prompt in
            UpgradePromptSheet(prompt: prompt) { upgradePromptToShow = nil }
        }
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        Text(message.text)
            .font(LuxuryTheme.bodyFont(size: 15))
            .padding(12)
            .background(
                message.sender == .user
                    ? LuxuryTheme.surfaceCard
                    : Color(red: 1, green: 122/255, blue: 89/255, opacity: 0.12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
            )
            .foregroundColor(AppColors.textPrimary)
            .cornerRadius(14)
            .frame(maxWidth: 280, alignment: message.sender == .user ? .leading : .trailing)
    }

    private var resumeIntakeButton: some View {
        Button {
            chatViewModel.resumeIntake()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.clipboard.fill")
                Text("Resume intake")
                    .font(LuxuryTheme.buttonFont(size: 14))
            }
        }
        .buttonStyle(AppButtonStyle())
    }

    @ViewBuilder
    private func documentOfferButton(for message: ChatMessage) -> some View {
        Button {
            guard let caseFolder = caseTreeViewModel.selectedCase else { return }
            let docCount = caseTreeViewModel.files(for: caseFolder.id, subfolder: caseTreeViewModel.selectedSubfolder).count
            let usage = PremiumUsage(documentCountInCase: docCount, evidenceCountInCase: 0)
            if !PremiumAccessManager.canAccess(.documentGeneration, hasFullAccess: subscriptionViewModel.hasFullAccess, usage: usage) {
                upgradePromptToShow = PremiumAccessManager.upgradePrompt(for: .documentGeneration)
                return
            }
            let name = "Draft \(Date().formatted(date: .abbreviated, time: .omitted))"
            let content = "This is a placeholder for the generated document. When the real API is connected, the AI will fill this with the actual draft.\n\nGenerated by Ask AI Lawyer."
            if caseTreeViewModel.addGeneratedDocument(caseId: caseFolder.id, subfolder: caseTreeViewModel.selectedSubfolder, name: name, content: content) != nil {
                let confirmText = "I've added \"\(name)\" to your selected folder and timeline. Open the folder in the sidebar to view it, or open Timeline to see the event."
                conversationManager.addMessage(Message(id: UUID(), caseId: caseFolder.id, role: "assistant", content: confirmText, timestamp: Date()))
            }
        } label: {
            Text("Yes, generate document")
                .font(LuxuryTheme.buttonFont(size: 14))
        }
        .buttonStyle(AppButtonStyle())
    }
}

// MARK: - Case Overview (card-based workspace layout)
struct CaseOverviewView: View {
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @State private var nextAction: NextAction?
    @State private var nextActionLoading = false
    @State private var nextActionError: String?
    @State private var upgradePromptToShow: UpgradePrompt?
    @State private var showInviteSheet = false
    @State private var currentInvitation: CaseInvitation?
    private static let progressEngine = CaseProgressEngine()
    private static let nextActionEngine = NextActionEngine()
    private static let referralEngine = AttorneyReferralEngine()

    var body: some View {
        Group {
            if let state = workspace.currentCaseState, let analysis = state.analysis {
                VStack(spacing: 0) {
                    caseCommandBar(onNextAction: fetchNextAction)

                    ScrollView {
                        VStack(alignment: .leading, spacing: LuxuryTheme.workspaceCardSpacing) {
                            if let action = nextAction {
                                nextActionCard(action)
                            }

                            CaseBriefView(analysis: analysis)

                            if let caseId = workspace.selectedCaseId,
                               let referral = Self.referralEngine.recommendReferral(caseId: caseId, analysis: analysis, evidenceCount: state.evidence.count) {
                                attorneyReferralCard(referral)
                            }

                            CaseProgressView(progress: Self.progressEngine.generateInitialProgress())

                            SuggestedActionsCardView(
                                analysis: analysis,
                                onSuggestedAction: { section in
                                    workspace.caseTreeViewModel.selectedWorkspaceSection = section
                                    if let sub = section.documentSubfolder {
                                        workspace.caseTreeViewModel.selectedSubfolder = sub
                                    }
                                }
                            )

                            EvidenceAlertsView(alerts: state.evidenceAlerts)

                            LegalArgumentsView(arguments: state.legalArguments)

                            CaseDashboardView(
                                analysis: analysis,
                                deadlines: state.deadlines,
                                strategy: state.litigationStrategy,
                                confidence: state.confidence,
                                showSuggestedActions: false,
                                headerIcon: "📄",
                                headerTitle: "Case Dashboard",
                                hasFullAccess: subscriptionViewModel.hasFullAccess,
                                onUpgradeRequested: { upgradePromptToShow = PremiumAccessManager.upgradePrompt(for: .advancedLitigationStrategy) }
                            )

                            CaseActivityTimelineView(activities: [])
                        }
                        .padding(LuxuryTheme.workspaceCardSpacing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.primary)
                    Text("No case analysis yet")
                        .font(LuxuryTheme.sectionFont(size: 17))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Use Chat to describe your case or add a voice recording. Analysis will appear here.")
                        .font(LuxuryTheme.bodyFont(size: 14))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.background)
        .sheet(item: $upgradePromptToShow) { prompt in
            UpgradePromptSheet(prompt: prompt) { upgradePromptToShow = nil }
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteParticipantSheet
        }
    }

    private var inviteParticipantSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Share this link with the person you want to invite. They will have access only to this case and can upload evidence or record statements.")
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let inv = currentInvitation {
                    let link = workspace.caseCollaborationEngine.invitationURL(for: inv.token)
                    Text(link)
                        .font(LuxuryTheme.bodyFont(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LuxuryTheme.surfaceCard)
                        .cornerRadius(10)

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = link
                        } label: {
                            Label("Copy link", systemImage: "doc.on.doc")
                                .font(LuxuryTheme.buttonFont(size: 15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppButtonStyle())

                        Button {
                            let av = UIActivityViewController(activityItems: [link], applicationActivities: nil)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let root = windowScene.windows.first?.rootViewController {
                                root.present(av, animated: true)
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(LuxuryTheme.buttonFont(size: 15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppButtonStyle())
                    }
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LuxuryTheme.primaryBackground)
            .navigationTitle("Invite Participant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showInviteSheet = false
                        currentInvitation = nil
                    }
                }
            }
        }
    }

    private func caseCommandBar(onNextAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {
                onNextAction()
            } label: {
                HStack(spacing: 8) {
                    if nextActionLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.textPrimary))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "lightbulb.fill")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.primary)
                    }
                    Text("What Should I Do Next?")
                        .font(LuxuryTheme.bodyFont(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(LuxuryTheme.surfaceCard)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(nextActionLoading)

            if let caseId = workspace.selectedCaseId {
                Button {
                    let inv = workspace.caseCollaborationEngine.createInvitation(caseId: caseId)
                    currentInvitation = inv
                    showInviteSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.primary)
                        Text("Invite Participant")
                            .font(LuxuryTheme.bodyFont(size: 15))
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(LuxuryTheme.surfaceCard)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, LuxuryTheme.workspaceCardSpacing)
        .padding(.vertical, 12)
        .background(AppColors.background)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(LuxuryTheme.navBarBorder),
            alignment: .bottom
        )
    }

    private func nextActionCard(_ action: NextAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(action.title)
                    .font(LuxuryTheme.sectionFont(size: 17))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button {
                    nextAction = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppColors.textPrimary)
                }
                .buttonStyle(.plain)
            }
            Text(action.description)
                .font(LuxuryTheme.bodyFont(size: 15))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private func attorneyReferralCard(_ referral: AttorneyReferral) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceCardHeader(icon: "👨‍⚖️", title: "Attorney Referral")
            Rectangle()
                .fill(AppColors.cardStroke)
                .frame(height: 1)
            Text(referral.recommendation)
                .font(LuxuryTheme.bodyFont(size: 15))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button(AttorneyReferralEngine.connectButtonTitle) {
                if !PremiumAccessManager.canAccess(.attorneyReferralConnections, hasFullAccess: subscriptionViewModel.hasFullAccess) {
                    upgradePromptToShow = PremiumAccessManager.upgradePrompt(for: .attorneyReferralConnections)
                    return
                }
                // TODO: Open attorney referral flow (directory, contact form, or partner link)
            }
            .buttonStyle(AppButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private func fetchNextAction() {
        guard let state = workspace.currentCaseState, let analysis = state.analysis else { return }
        nextActionError = nil
        nextActionLoading = true
        let evidenceSummaries: [EvidenceAnalysis] = state.evidence.map { file in
            let summary = (file.content?.trimmingCharacters(in: .whitespacesAndNewlines))
                .map { $0.count > 500 ? String($0.prefix(500)) + "…" : $0 }
                ?? file.name
            return EvidenceAnalysis(
                summary: summary,
                violations: [],
                damages: nil,
                timelineEvents: [],
                deadlines: [],
                missingEvidence: nil
            )
        }
        let timeline = analysis.timeline
        let engine = Self.nextActionEngine
        Task.detached(priority: .userInitiated) {
            do {
                let action = try await engine.recommendNextAction(
                    caseAnalysis: analysis,
                    evidence: evidenceSummaries,
                    timeline: timeline
                )
                await MainActor.run {
                    nextAction = action
                    nextActionLoading = false
                }
            } catch {
                await MainActor.run {
                    nextActionError = error.localizedDescription
                    nextActionLoading = false
                }
            }
        }
    }
}

// MARK: - Placeholder for workspace sections (Emails, Deadlines, Tasks)
struct WorkspacePlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text(title)
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text(message)
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}
