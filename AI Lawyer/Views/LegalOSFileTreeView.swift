import SwiftUI

/// Case/file sidebar tree. **Initializer:** `LegalOSFileTreeView(isCollapsed:)` only — do not pass `chatViewModel` (use `@EnvironmentObject` from an ancestor if needed).
struct LegalOSFileTreeView: View {
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var conversationManager: ConversationManager
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isCollapsed: Bool
    @State private var searchText: String = ""

    // Expand/collapse state
    @State private var expandedCaseIds: Set<UUID> = []
    @State private var expandedFolderKeys: Set<String> = []

    // Star state (persists via UserDefaults)
    @AppStorage("legal_os_starred_items") private var starredItemsJSON: String = "[]"
    @State private var starredItems: Set<String> = []

    // File actions
    private struct FileActionTarget: Equatable {
        let caseId: UUID
        let subfolder: CaseSubfolder
        let fileId: UUID
    }

    @State private var renameTarget: FileActionTarget?
    @State private var renameDraftName: String = ""
    @State private var showRenameSheet = false

    @State private var deleteTarget: FileActionTarget?
    @State private var showDeleteConfirmation = false
    @State private var scrollingNameKey: String? = nil

    private var caseTreeViewModel: CaseTreeViewModel { workspace.caseTreeViewModel }

    private struct SidebarStyle {
        static let sidebarBgDark = Color(red: 32/255, green: 33/255, blue: 36/255)   // #202124
        static let sidebarBgLight = Color(red: 243/255, green: 244/255, blue: 246/255) // #F3F4F6
        static let activeHighlight = Color(red: 59/255, green: 130/255, blue: 246/255, opacity: 0.12)
        static let rowCornerRadius: CGFloat = 10
    }

    private var showText: Bool { !isCollapsed }
    private var rootSpacing: CGFloat { isCollapsed ? 8 : 10 }
    private var rowPaddingV: CGFloat { isCollapsed ? 7 : 8 }
    private var rowPaddingH: CGFloat { isCollapsed ? 6 : 10 }

    var body: some View {
        VStack(spacing: rootSpacing) {
            // Collapse toggle (icon-only mode)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isCollapsed.toggle() }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(AppTapButtonStyle())
                .accessibilityLabel(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            // Search bar
            if showText {
                HStack(spacing: 8) {
                    Image("PocketLawLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text("Pocket Lawyer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)

                TextField("Search", text: $searchText)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(10)
                    .background(LuxuryTheme.surfaceCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 12)
                    .padding(.top, 0)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                    TextField("", text: $searchText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(LuxuryTheme.surfaceCard)
                .cornerRadius(12)
                .padding(.horizontal, 10)
            }

            // File tree
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    let term = searchTerm
                    if term.isEmpty {
                        if showText {
                            Text("Cases")
                                .font(AppTypography.bodySemibold)
                                .foregroundColor(AppColors.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                        }

                        ForEach(caseTreeViewModel.orderedCases) { folder in
                            caseNode(folder)
                        }
                    } else {
                        searchResultsView(term: term)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.automatic)
            Spacer(minLength: 0)
            ThemeModeToggleButton(size: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.bottom, 10)
        }
        .background(colorScheme == .dark ? SidebarStyle.sidebarBgDark : SidebarStyle.sidebarBgLight)
        .onAppear {
            starredItems = decodeStarredItems(from: starredItemsJSON)
            if let selected = caseTreeViewModel.selectedCase?.id, caseTreeViewModel.cases.contains(where: { $0.id == selected }) {
                expandedCaseIds.insert(selected)
            }
        }
        .onChange(of: starredItems) { _, _ in
            starredItemsJSON = encodeStarredItems(starredItems)
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rename file")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Name", text: $renameDraftName)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.body)

                    Spacer()
                }
                .padding(20)
                .background(AppColors.background)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showRenameSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let target = renameTarget {
                                caseTreeViewModel.renameFile(caseId: target.caseId, subfolder: target.subfolder, fileId: target.fileId, newName: renameDraftName)
                            }
                            showRenameSheet = false
                        }
                        .disabled(renameDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    caseTreeViewModel.deleteFile(caseId: target.caseId, subfolder: target.subfolder, fileId: target.fileId)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        }
    }

    private var searchTerm: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private enum SearchHitKind {
        case caseItem
        case fileItem
        case chatItem
    }

    private struct SearchHit: Identifiable {
        let id: String
        let kind: SearchHitKind
        let title: String
        let subtitle: String?
        let caseId: UUID
        let subfolder: CaseSubfolder
        let fileId: UUID?
    }

    @ViewBuilder
    private func searchResultsView(term: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !caseSearchHits.isEmpty {
                if showText {
                    Text("Cases")
                        .font(AppTypography.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 12)
                }

                ForEach(caseSearchHits) { hit in
                    Button {
                        selectSearchHit(hit)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundColor(AppColors.primary)
                                .font(.system(size: 16, weight: .semibold))
                            if showText {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(AppTypography.bodySemibold)
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(1)
                                    if let subtitle = hit.subtitle {
                                        Text(subtitle)
                                            .font(AppTypography.body)
                                            .foregroundColor(AppColors.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(SidebarStyle.activeHighlight)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !fileSearchHits.isEmpty {
                if showText {
                    Text("Files")
                        .font(AppTypography.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 12)
                }

                ForEach(fileSearchHits) { hit in
                    Button {
                        selectSearchHit(hit)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundColor(AppColors.primary)
                                .font(.system(size: 16, weight: .semibold))
                            if showText {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(AppTypography.bodySemibold)
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(1)
                                    if let subtitle = hit.subtitle {
                                        Text(subtitle)
                                            .font(AppTypography.body)
                                            .foregroundColor(AppColors.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(SidebarStyle.activeHighlight)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !chatSearchHits.isEmpty {
                if showText {
                    Text("Chat")
                        .font(AppTypography.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 12)
                }

                ForEach(chatSearchHits) { hit in
                    Button {
                        selectSearchHit(hit)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundColor(AppColors.primary)
                                .font(.system(size: 16, weight: .semibold))
                            if showText {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(AppTypography.bodySemibold)
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(1)
                                    if let subtitle = hit.subtitle {
                                        Text(subtitle)
                                            .font(AppTypography.body)
                                            .foregroundColor(AppColors.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(SidebarStyle.activeHighlight)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private var caseSearchHits: [SearchHit] {
        let term = searchTerm
        guard !term.isEmpty else { return [] }
        return caseTreeViewModel.cases
            .filter { $0.title.lowercased().contains(term) }
            .prefix(10)
            .map { folder in
                SearchHit(
                    id: "case|\(folder.id.uuidString)",
                    kind: .caseItem,
                    title: folder.title,
                    subtitle: "Open case",
                    caseId: folder.id,
                    subfolder: .evidence,
                    fileId: nil
                )
            }
    }

    private var fileSearchHits: [SearchHit] {
        let term = searchTerm
        guard !term.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for folder in caseTreeViewModel.cases {
            for (subfolder, files) in folder.subfolders {
                for file in files {
                    let nameMatch = file.name.lowercased().contains(term)
                    let contentMatch = file.content?.lowercased().contains(term) ?? false
                    guard nameMatch || contentMatch else { continue }

                    let subtitle: String? = {
                        if let content = file.content, contentMatch {
                            let preview = content.trimmingCharacters(in: .whitespacesAndNewlines)
                            return preview.count > 70 ? String(preview.prefix(70)) + "…" : preview
                        }
                        return subfolder.rawValue
                    }()

                    hits.append(
                        SearchHit(
                            id: "file|\(folder.id.uuidString)|\(subfolder.rawValue)|\(file.id.uuidString)",
                            kind: .fileItem,
                            title: file.name,
                            subtitle: subtitle,
                            caseId: folder.id,
                            subfolder: subfolder,
                            fileId: file.id
                        )
                    )
                }
            }
        }
        return hits.prefix(30).map { $0 }
    }

    private var chatSearchHits: [SearchHit] {
        let term = searchTerm
        guard !term.isEmpty else { return [] }

        // Search chat contents; tie back to file version when `message.fileId` exists.
        let hits = conversationManager.messages.compactMap { message -> SearchHit? in
            guard let cid = message.caseId else { return nil }
            guard message.content.lowercased().contains(term) else { return nil }

            let caseFolder = caseTreeViewModel.cases.first(where: { $0.id == cid })
            let (subfolder, fileIdFromMessage) = resolveSubfolderAndFileId(caseFolder: caseFolder, fileId: message.fileId)
            let title = (message.role == "user") ? "User: \(message.content.prefix(38))" : "AI: \(message.content.prefix(38))"
            let subtitle = message.content.count > 90 ? String(message.content.prefix(90)) + "…" : message.content

            return SearchHit(
                id: "chat|\(cid.uuidString)|\(message.id.uuidString)",
                kind: .chatItem,
                title: String(title),
                subtitle: subtitle,
                caseId: cid,
                subfolder: subfolder,
                fileId: fileIdFromMessage
            )
        }
        return hits.prefix(20).map { $0 }
    }

    private func resolveSubfolderAndFileId(caseFolder: CaseFolder?, fileId: UUID?) -> (CaseSubfolder, UUID?) {
        guard let caseFolder else { return (.evidence, fileId) }
        guard let fileId else { return (.evidence, nil) }

        for (subfolder, files) in caseFolder.subfolders {
            if files.contains(where: { $0.id == fileId }) {
                return (subfolder, fileId)
            }
        }
        return (.evidence, fileId)
    }

    private func selectSearchHit(_ hit: SearchHit) {
        switch hit.kind {
        case .caseItem:
            if let folder = caseTreeViewModel.cases.first(where: { $0.id == hit.caseId }) {
                workspace.selectCase(byFolder: folder)
                caseTreeViewModel.selectedCase = folder
                caseTreeViewModel.selectedSubfolder = hit.subfolder
                caseTreeViewModel.selectedFileId = nil
                expandedCaseIds.insert(hit.caseId)
            }
        case .fileItem:
            if let folder = caseTreeViewModel.cases.first(where: { $0.id == hit.caseId }) {
                workspace.selectCase(byFolder: folder)
                caseTreeViewModel.selectedCase = folder
                caseTreeViewModel.selectedSubfolder = hit.subfolder
                caseTreeViewModel.selectedFileId = hit.fileId
                expandedCaseIds.insert(hit.caseId)
                expandedFolderKeys.insert(expandedFolderKey(for: hit.caseId, subfolder: hit.subfolder))
            }
        case .chatItem:
            if let folder = caseTreeViewModel.cases.first(where: { $0.id == hit.caseId }) {
                workspace.selectCase(byFolder: folder)
                caseTreeViewModel.selectedCase = folder
                caseTreeViewModel.selectedSubfolder = hit.subfolder
                caseTreeViewModel.selectedFileId = hit.fileId
                expandedCaseIds.insert(hit.caseId)
                if let fileId = hit.fileId {
                    expandedFolderKeys.insert(expandedFolderKey(for: hit.caseId, subfolder: hit.subfolder))
                    _ = fileId
                }
            }
        }
    }

    private func expandedFolderKey(for caseId: UUID, subfolder: CaseSubfolder) -> String {
        let title: String = {
            switch subfolder {
            case .evidence: return "Evidence"
            case .documents: return "Documents"
            case .response: return "Responses"
            case .history: return "Knowledge"
            case .filedDocuments: return "Archive"
            default: return subfolder.rawValue
            }
        }()
        return "\(caseId.uuidString)|\(subfolder.rawValue)|\(title)"
    }

    // MARK: - Nodes

    private func caseNode(_ folder: CaseFolder) -> some View {
        let isExpanded = expandedCaseIds.contains(folder.id)
        let isActiveCase = caseTreeViewModel.selectedCase?.id == folder.id

        return VStack(alignment: .leading, spacing: isCollapsed ? 4 : 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedCaseIds = expandedCaseIds.symmetricDifference([folder.id])
                    // Selecting a case clears active file (subfolder selection remains as set).
                    workspace.selectCase(byFolder: folder)
                    caseTreeViewModel.selectedFileId = nil
                }
            } label: {
                HStack(spacing: showText ? 8 : 0) {
                    Image(systemName: "folder")
                        .foregroundColor(isActiveCase ? AppColors.primary : AppColors.textSecondary)
                        .font(.system(size: 16, weight: .semibold))
                    if showText {
                        sidebarNameLabel(
                            folder.title,
                            key: "case|\(folder.id.uuidString)",
                            font: AppTypography.bodySemibold,
                            color: AppColors.textPrimary
                        )
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(AppColors.textSecondary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, rowPaddingH)
                .padding(.vertical, rowPaddingV)
                .background(isActiveCase ? SidebarStyle.activeHighlight : Color.clear)
                .cornerRadius(SidebarStyle.rowCornerRadius)
            }
            .buttonStyle(AppTapButtonStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    triggerNameReveal(for: "case|\(folder.id.uuidString)")
                }
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    folderCategoryNode(caseId: folder.id, title: "Evidence", systemName: "doc.text", subfolder: .evidence)
                    folderCategoryNode(caseId: folder.id, title: "Documents", systemName: "doc.text", subfolder: .documents)
                    folderCategoryNode(caseId: folder.id, title: "Templates", systemName: "doc.text", subfolder: .documents)
                    folderCategoryNode(caseId: folder.id, title: "Responses", systemName: "doc.text", subfolder: .response)
                    folderCategoryNode(caseId: folder.id, title: "Knowledge", systemName: "doc.text", subfolder: .history)
                    folderCategoryNode(caseId: folder.id, title: "Archive", systemName: "doc.text", subfolder: .filedDocuments)
                }
                .padding(.leading, showText ? 12 : 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func folderCategoryNode(
        caseId: UUID,
        title: String,
        systemName: String,
        subfolder: CaseSubfolder
    ) -> some View {
        let folderKey = "\(caseId.uuidString)|\(subfolder.rawValue)|\(title)"

        let isExpanded = expandedFolderKeys.contains(folderKey)
        let isActiveFolder = caseTreeViewModel.selectedCase?.id == caseId && caseTreeViewModel.selectedSubfolder == subfolder

        let files = caseTreeViewModel.files(for: caseId, subfolder: subfolder)

        return VStack(alignment: .leading, spacing: isCollapsed ? 4 : 6) {
            HStack(spacing: showText ? 8 : 0) {
                Image(systemName: "folder")
                    .foregroundColor(isActiveFolder ? AppColors.primary : AppColors.textSecondary)
                    .font(.system(size: 16, weight: .semibold))

                if showText {
                    sidebarNameLabel(
                        title,
                        key: "folder|\(caseId.uuidString)|\(subfolder.rawValue)|\(title)",
                        font: AppTypography.body,
                        color: AppColors.textPrimary
                    )
                }

                Spacer(minLength: 0)

                // Star (important)
                starButton(forKey: folderKey)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(AppColors.textSecondary)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, rowPaddingH)
            .padding(.vertical, rowPaddingV)
            .background(isActiveFolder ? SidebarStyle.activeHighlight : Color.clear)
            .cornerRadius(SidebarStyle.rowCornerRadius)
            .contentShape(Rectangle())
            .onTapGesture {
                triggerNameReveal(for: "folder|\(caseId.uuidString)|\(subfolder.rawValue)|\(title)")
                withAnimation(.easeInOut(duration: 0.18)) {
                    // Expand/collapse and select folder
                    expandedFolderKeys = expandedFolderKeys.symmetricDifference([folderKey])
                    workspace.selectedCaseId = caseId
                    caseTreeViewModel.selectedCase = caseTreeViewModel.cases.first(where: { $0.id == caseId })
                    caseTreeViewModel.selectedSubfolder = subfolder
                    caseTreeViewModel.selectedFileId = files.max(by: { $0.createdAt < $1.createdAt })?.id
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    triggerNameReveal(for: "folder|\(caseId.uuidString)|\(subfolder.rawValue)|\(title)")
                }
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if files.isEmpty {
                        if showText {
                            Text("No files")
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                        }
                    } else {
                        ForEach(files.prefix(30)) { file in
                            let isActiveFile = caseTreeViewModel.selectedCase?.id == caseId &&
                                caseTreeViewModel.selectedSubfolder == subfolder &&
                                caseTreeViewModel.selectedFileId == file.id

                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundColor(isActiveFile ? AppColors.primary : AppColors.textSecondary)
                                    .font(.system(size: 16, weight: .semibold))
                                if showText {
                                    sidebarNameLabel(
                                        file.name,
                                        key: "file|\(caseId.uuidString)|\(subfolder.rawValue)|\(file.id.uuidString)",
                                        font: AppTypography.body,
                                        color: AppColors.textPrimary
                                    )
                                }
                                Spacer(minLength: 0)
                                starButton(forKey: fileStarKey(caseId: caseId, subfolder: subfolder, fileId: file.id))
                            }
                            .padding(.horizontal, showText ? 10 : 6)
                            .padding(.vertical, 6)
                            .background(isActiveFile ? SidebarStyle.activeHighlight : Color.clear)
                            .cornerRadius(SidebarStyle.rowCornerRadius)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                triggerNameReveal(for: "file|\(caseId.uuidString)|\(subfolder.rawValue)|\(file.id.uuidString)")
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    workspace.selectedCaseId = caseId
                                    caseTreeViewModel.selectedCase = caseTreeViewModel.cases.first(where: { $0.id == caseId })
                                    caseTreeViewModel.selectedSubfolder = subfolder
                                    caseTreeViewModel.selectedFileId = file.id
                                }
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                    triggerNameReveal(for: "file|\(caseId.uuidString)|\(subfolder.rawValue)|\(file.id.uuidString)")
                                }
                            )
                            .contextMenu {
                                if let n = file.versionNumber,
                                   n > 1,
                                   file.content != nil {
                                    Button {
                                        caseTreeViewModel.rollbackFileVersion(caseId: caseId, subfolder: subfolder, fileId: file.id)
                                    } label: {
                                        Label("Rollback to v\(n)", systemImage: "arrow.uturn.backward.circle")
                                    }
                                }

                                Divider()

                                Button {
                                    renameTarget = FileActionTarget(caseId: caseId, subfolder: subfolder, fileId: file.id)
                                    renameDraftName = file.name
                                    showRenameSheet = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Menu("Move to") {
                                    Button("Evidence") {
                                        caseTreeViewModel.moveFile(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .evidence, fileId: file.id)
                                    }
                                    Button("Documents") {
                                        caseTreeViewModel.moveFile(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .documents, fileId: file.id)
                                    }
                                    Button("Responses") {
                                        caseTreeViewModel.moveFile(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .response, fileId: file.id)
                                    }
                                    Button("Knowledge") {
                                        caseTreeViewModel.moveFile(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .history, fileId: file.id)
                                    }
                                    Button("Archive") {
                                        caseTreeViewModel.moveFile(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .filedDocuments, fileId: file.id)
                                    }
                                }

                                Button {
                                    _ = caseTreeViewModel.duplicateFile(caseId: caseId, subfolder: subfolder, fileId: file.id)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }

                                Button(role: .destructive) {
                                    deleteTarget = FileActionTarget(caseId: caseId, subfolder: subfolder, fileId: file.id)
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.leading, showText ? 8 : 4)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }

            private func fileStarKey(caseId: UUID, subfolder: CaseSubfolder, fileId: UUID) -> String {
                "\(caseId.uuidString)|\(subfolder.rawValue)|\(fileId.uuidString)"
            }

            private func starButton(forKey key: String) -> some View {
                let isStarred = starredItems.contains(key)
                return Button {
                    if isStarred {
                        starredItems.remove(key)
                    } else {
                        starredItems.insert(key)
                    }
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundColor(isStarred ? AppColors.primary : AppColors.textSecondary)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(AppTapButtonStyle())
                .accessibilityLabel(isStarred ? "Unstar" : "Star")
            }

            @ViewBuilder
            private func sidebarNameLabel(_ text: String, key: String, font: Font, color: Color) -> some View {
                if scrollingNameKey == key {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            private func triggerNameReveal(for key: String) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollingNameKey = key
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    if scrollingNameKey == key {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scrollingNameKey = nil
                        }
                    }
                }
            }

            private func moveDestinationButton(_ title: String, _ destination: CaseSubfolder) -> some View {
                EmptyView()
            }

            // MARK: - Persistence for stars
            private func decodeStarredItems(from json: String) -> Set<String> {
                guard let data = json.data(using: .utf8),
                    let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                return Set(arr)
            }

            private func encodeStarredItems(_ set: Set<String>) -> String {
                let arr = Array(set)
                guard let data = try? JSONEncoder().encode(arr) else { return "[]" }
                return String(data: data, encoding: .utf8) ?? "[]"
            }
        }

