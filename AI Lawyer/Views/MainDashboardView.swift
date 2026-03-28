import SwiftUI
import UIKit
import UniformTypeIdentifiers

private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Fixed header (composed in `RootContainerView`; does not slide with sidebar)

struct TopBarView: View {
    @Binding var showHamburgerMenu: Bool
    @AppStorage("isDarkMode") private var isDarkMode = true

    private var panelBackground: Color { isDarkMode ? AppColors.darkBackground : AppColors.lightBackground }
    private var primaryTextColor: Color { isDarkMode ? .white : .black }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("AppLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text("Pocket Lawyer")
                    .font(.headline)
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                Spacer()

                HamburgerMenuButton(showMenu: $showHamburgerMenu, tint: primaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .background(panelBackground)
    }
}

private struct HamburgerMenuButton: View {
    @Binding var showMenu: Bool
    var tint: Color

    var body: some View {
        Button {
            showMenu = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title2)
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}

/// Main workspace body (scroll content only). Top bar lives in `RootContainerView`. `ChatInputBar` is a bottom `safeAreaInset` there.
///
/// Memberwise order: `selectedWorkspaceItem`, `showAddEvidenceSheet`, `showHamburgerMenu`, `chatViewModel`.
struct MainContentView: View {
    @Binding var selectedWorkspaceItem: SidebarWorkspaceItem
    @Binding var showAddEvidenceSheet: Bool
    @Binding var showHamburgerMenu: Bool

    @ObservedObject var chatViewModel: ChatViewModel

    @EnvironmentObject var workspace: WorkspaceManager
    @StateObject private var learningViewModel = LearningViewModel()
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @Environment(\.colorScheme) private var colorScheme

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
        ZStack {
            CaseWorkspaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isDarkMode ? AppColors.darkBackground : AppColors.lightBackground)
                .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showAddEvidenceSheet) {
            AddEvidenceView()
        }
        .onAppear {
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
    case generalLawQuestions = "General Law Questions"
    case exampleCase = "Jones vs. Smith (Example Case)"
    case trustLaw = "Trust Law"
    case civilLaw = "Civil Law"
    case realEstateLaw = "Real Estate Law"
    case familyTrustDocuments = "Family Trust Documents"
    case dufffVsBanks = "Dufff Vs. Banks"
}

struct SidebarView: View {
    @Binding var showAddEvidenceSheet: Bool
    @Binding var selectedItem: SidebarWorkspaceItem
    @EnvironmentObject var workspace: WorkspaceManager
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var expandedCaseIds: Set<UUID> = []
    @State private var newPrimaryFolderName = ""
    @State private var newSecondaryFolderName = ""
    @State private var isAddingPrimaryFolder = false
    @State private var isAddingSecondaryFolder = false
    @State private var renameCaseTarget: UUID?
    @State private var renameCaseName = ""
    @State private var renameSubfolderTarget: (caseId: UUID, subfolder: CaseSubfolder)?
    @State private var renameSubfolderName = ""
    @State private var addingSubfolderTarget: UUID?

    private var caseTreeViewModel: CaseTreeViewModel { workspace.caseTreeViewModel }
    private let primarySectionOrder = [
        "General Law Questions",
        "Jones vs. Smith (Example Case)",
        "Trust Law",
        "Civil Law",
        "Real Estate Law"
    ]
    private let secondarySectionOrder = [
        "Family Trust Documents",
        "Dufff Vs. Banks"
    ]

    private var casesAndResearchFolders: [CaseFolder] {
        sortFolders(caseTreeViewModel.cases.filter { $0.category == .inProgress }, using: primarySectionOrder)
    }
    private var myCasesAndVitalDocumentsFolders: [CaseFolder] {
        sortFolders(caseTreeViewModel.cases.filter { $0.category == .mockCases }, using: secondarySectionOrder)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text("Cases & Research")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isDarkMode ? .white : .black)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Button {
                        isAddingPrimaryFolder.toggle()
                        if !isAddingPrimaryFolder { newPrimaryFolderName = "" }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.primaryAccent)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(casesAndResearchFolders) { folder in
                        caseFolderItem(folder)
                    }
                    if isAddingPrimaryFolder {
                        newCaseField(title: "New folder name", text: $newPrimaryFolderName) {
                            let id = caseTreeViewModel.createNewCase(title: newPrimaryFolderName, category: .inProgress)
                            if let folder = caseTreeViewModel.cases.first(where: { $0.id == id }) {
                                workspace.selectCase(byFolder: folder)
                                expandedCaseIds.insert(id)
                            }
                            newPrimaryFolderName = ""
                            isAddingPrimaryFolder = false
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                .cornerRadius(12)

                Divider()
                    .background(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                HStack(spacing: 10) {
                    Text("My Cases & Vital Documents")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isDarkMode ? .gray : .secondary)

                    Button {
                        isAddingSecondaryFolder.toggle()
                        if !isAddingSecondaryFolder { newSecondaryFolderName = "" }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.primaryAccent)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(myCasesAndVitalDocumentsFolders) { folder in
                        caseFolderItem(folder)
                    }
                    if isAddingSecondaryFolder {
                        newCaseField(title: "New folder name", text: $newSecondaryFolderName) {
                            let id = caseTreeViewModel.createNewCase(title: newSecondaryFolderName, category: .mockCases)
                            if let folder = caseTreeViewModel.cases.first(where: { $0.id == id }) {
                                workspace.selectCase(byFolder: folder)
                                expandedCaseIds.insert(id)
                            }
                            newSecondaryFolderName = ""
                            isAddingSecondaryFolder = false
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                .cornerRadius(12)
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            isDarkMode
                ? AppColors.darkBackground
                : Color(red: 235/255, green: 235/255, blue: 240/255)
        )
        .clipped()
        .onAppear {
            if let selectedId = caseTreeViewModel.selectedCase?.id {
                expandedCaseIds.insert(selectedId)
            }
            if let generalFolder = caseTreeViewModel.cases.first(where: { $0.title == SidebarWorkspaceItem.generalLawQuestions.rawValue }) {
                workspace.selectCase(byFolder: generalFolder)
                expandedCaseIds.insert(generalFolder.id)
            }
        }
    }

    private func sidebarItem(_ item: SidebarWorkspaceItem) -> some View {
        Button {
            selectedItem = item
        } label: {
            SidebarCaseRow(
                title: item.rawValue,
                subtitle: "Questions • Documents • Strategies",
                isSelected: selectedItem == item,
                isDarkMode: isDarkMode
            )
        }
        .buttonStyle(.plain)
    }

    private func caseFolderItem(_ folder: CaseFolder) -> some View {
        let isExpanded = expandedCaseIds.contains(folder.id)
        let isSelected = caseTreeViewModel.selectedCase?.id == folder.id

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedCaseIds.remove(folder.id)
                    } else {
                        expandedCaseIds.insert(folder.id)
                    }
                    workspace.selectCase(byFolder: folder)
                    caseTreeViewModel.selectedWorkspaceSection = .overview
                }
            } label: {
                SidebarCaseRow(
                    title: folder.title,
                    subtitle: "Questions • Documents • Strategies",
                    isSelected: isSelected,
                    isDarkMode: isDarkMode
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename") {
                    renameCaseTarget = folder.id
                    renameCaseName = folder.title
                }
                Button("Delete", role: .destructive) {
                    caseTreeViewModel.deleteCase(id: folder.id)
                    expandedCaseIds.remove(folder.id)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    caseSectionItem("Ask", section: .overview, caseFolder: folder)
                    ForEach(caseTreeViewModel.visibleSubfolders(caseId: folder.id), id: \.self) { subfolder in
                        caseSubfolderItem(subfolder, caseFolder: folder)
                    }
                    caseSectionItem("Tasks", section: .tasks, caseFolder: folder)
                    caseSectionItem("Chat", section: .chat, caseFolder: folder)
                    Menu {
                        ForEach(caseTreeViewModel.availableHiddenSubfolders(caseId: folder.id), id: \.self) { subfolder in
                            Button("Add \(caseTreeViewModel.folderDisplayName(caseId: folder.id, subfolder: subfolder))") {
                                caseTreeViewModel.setSubfolderHidden(caseId: folder.id, subfolder: subfolder, hidden: false)
                            }
                        }
                    } label: {
                        Label("Add Subfolder", systemImage: "plus.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.primaryAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    if renameCaseTarget == folder.id {
                        newCaseField(title: "Rename case", text: $renameCaseName) {
                            let trimmed = renameCaseName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            caseTreeViewModel.renameCase(id: folder.id, to: trimmed)
                            renameCaseTarget = nil
                            renameCaseName = ""
                        }
                    }
                    if let target = renameSubfolderTarget, target.caseId == folder.id {
                        newCaseField(title: "Rename subfolder", text: $renameSubfolderName) {
                            let trimmed = renameSubfolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            caseTreeViewModel.setFolderDisplayName(caseId: folder.id, subfolder: target.subfolder, name: trimmed)
                            renameSubfolderTarget = nil
                            renameSubfolderName = ""
                        }
                    }
                }
                .padding(.leading, 14)
            }
        }
    }

    private func caseSectionItem(_ title: String, section: CaseWorkspaceSection, caseFolder: CaseFolder) -> some View {
        let isSelected = caseTreeViewModel.selectedCase?.id == caseFolder.id &&
            caseTreeViewModel.selectedWorkspaceSection == section

        return Button {
            workspace.selectCase(byFolder: caseFolder)
            caseTreeViewModel.selectedWorkspaceSection = section
            syncSelection(for: section, caseFolder: caseFolder)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.textSecondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDarkMode ? .white : .black)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? (isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func caseSubfolderItem(_ subfolder: CaseSubfolder, caseFolder: CaseFolder) -> some View {
        let title = caseTreeViewModel.folderDisplayName(caseId: caseFolder.id, subfolder: subfolder)
        let isSelected = caseTreeViewModel.selectedCase?.id == caseFolder.id && caseTreeViewModel.selectedSubfolder == subfolder

        return Button {
            workspace.selectCase(byFolder: caseFolder)
            syncSelection(for: subfolder, caseFolder: caseFolder)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.textSecondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDarkMode ? .white : .black)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? (isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                renameSubfolderTarget = (caseFolder.id, subfolder)
                renameSubfolderName = title
            }
            Button("Delete", role: .destructive) {
                caseTreeViewModel.setSubfolderHidden(caseId: caseFolder.id, subfolder: subfolder, hidden: true)
            }
        }
    }

    private func syncSelection(for section: CaseWorkspaceSection, caseFolder: CaseFolder) {
        switch section {
        case .timeline, .tasks, .deadlines:
            caseTreeViewModel.selectedSubfolder = .timeline
            caseTreeViewModel.selectedFileId = caseTreeViewModel.files(for: caseFolder.id, subfolder: .timeline).max(by: { $0.createdAt < $1.createdAt })?.id
        case .evidence:
            caseTreeViewModel.selectedSubfolder = .evidence
            caseTreeViewModel.selectedFileId = caseTreeViewModel.files(for: caseFolder.id, subfolder: .evidence).max(by: { $0.createdAt < $1.createdAt })?.id
        case .documents:
            caseTreeViewModel.selectedSubfolder = .documents
            caseTreeViewModel.selectedFileId = caseTreeViewModel.files(for: caseFolder.id, subfolder: .documents).max(by: { $0.createdAt < $1.createdAt })?.id
        case .history:
            caseTreeViewModel.selectedSubfolder = .history
            caseTreeViewModel.selectedFileId = caseTreeViewModel.files(for: caseFolder.id, subfolder: .history).max(by: { $0.createdAt < $1.createdAt })?.id
        case .chat, .overview, .recordings, .emails:
            caseTreeViewModel.selectedFileId = nil
        }
    }

    private func syncSelection(for subfolder: CaseSubfolder, caseFolder: CaseFolder) {
        workspace.selectCase(byFolder: caseFolder)
        caseTreeViewModel.selectedSubfolder = subfolder
        caseTreeViewModel.selectedFileId = caseTreeViewModel.files(for: caseFolder.id, subfolder: subfolder).max(by: { $0.createdAt < $1.createdAt })?.id

        switch subfolder {
        case .timeline:
            caseTreeViewModel.selectedWorkspaceSection = .timeline
        case .evidence:
            caseTreeViewModel.selectedWorkspaceSection = .evidence
        case .documents, .filedDocuments, .response:
            caseTreeViewModel.selectedWorkspaceSection = .documents
        case .history:
            caseTreeViewModel.selectedWorkspaceSection = .history
        case .recordings:
            caseTreeViewModel.selectedWorkspaceSection = .recordings
        }
    }

    private func newCaseField(title: String, text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        TextField(title, text: text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isDarkMode ? .white : .black)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
            .cornerRadius(10)
            .onSubmit {
                guard !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                onSubmit()
            }
    }

    private func sortFolders(_ folders: [CaseFolder], using preferredOrder: [String]) -> [CaseFolder] {
        let lookup = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { ($1, $0) })
        return folders.sorted { lhs, rhs in
            let leftIndex = lookup[lhs.title] ?? Int.max
            let rightIndex = lookup[rhs.title] ?? Int.max
            if leftIndex == rightIndex {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return leftIndex < rightIndex
        }
    }
}

private struct SidebarCaseRow: View {
    let title: String
    let subtitle: String?
    var isSelected: Bool = false
    let isDarkMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundColor(AppColors.brandPurple.opacity(0.9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDarkMode ? .white : .black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)

                Text(subtitle ?? "Unfiled Draft")
                    .font(.system(size: 11))
                    .foregroundColor(isDarkMode ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
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
                .fill(
                    isSelected
                        ? (isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        : Color.clear
                )
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("• Build a mock case")
                    Text("• Ask a question")
                    Text("• Build a document")
                }
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(.gray)
                .lineSpacing(4)
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
        .background(isDarkMode ? AppColors.darkBackground : AppColors.lightBackground)
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
        return chatViewModel.messages
            .filter { msg in
                guard let caseId else { return msg.caseId == nil }
                return msg.caseId == caseId
            }
            .map { msg in
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
        .onChange(of: chatViewModel.messages.count) { _, count in
            print("UI RECEIVED MESSAGES:", count)
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
