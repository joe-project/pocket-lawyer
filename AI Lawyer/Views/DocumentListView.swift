import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import QuickLook
import Photos

/// Display order and display name for evidence categories in the Evidence view.
private let evidenceCategoryOrder: [(key: String, displayName: String)] = [
    (EvidenceCategorizationEngine.categoryPhotos, "Photos"),
    (EvidenceCategorizationEngine.categoryDocuments, "Documents"),
    (EvidenceCategorizationEngine.categoryMessages, "Messages"),
    (EvidenceCategorizationEngine.categoryWitnessStatements, "Witness Statements"),
    (EvidenceCategorizationEngine.categoryVideos, "Videos"),
]

struct DocumentListView: View {
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @State private var showAddDocument = false
    @State private var showImagePicker = false
    @State private var showFormImporter = false
    @State private var showFormImagePicker = false
    @State private var pickedImage: UIImage?
    @State private var newDocName = ""
    @State private var newDocContent = ""
    @State private var upgradePromptToShow: UpgradePrompt?
    @State private var importErrorMessage: String?
    @State private var isProcessingImportedDocument = false
    @State private var autofillSession: DocumentAutofillReviewSession?
    @State private var previewItem: PreviewFileItem?
    private let evidenceCategorizationEngine = EvidenceCategorizationEngine()
    private let documentProcessingService = DocumentProcessingService()
    private let documentAutofillService = DocumentAutofillService()
    private let completedDocumentWriter = CompletedDocumentWriter()

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

    var body: some View {
        Group {
            if let caseFolder = caseTreeViewModel.selectedCase {
                let subfolder = caseTreeViewModel.selectedSubfolder
                let folderName = caseTreeViewModel.folderDisplayName(caseId: caseFolder.id, subfolder: subfolder)
                let files = caseTreeViewModel.files(for: caseFolder.id, subfolder: subfolder)
                VStack(alignment: .leading, spacing: 0) {
                    header(folderName: folderName, caseId: caseFolder.id, subfolder: subfolder)
                    if subfolder == .evidence {
                        evidenceCategorizedContent(files: files, caseId: caseFolder.id)
                    } else if files.isEmpty {
                        emptyView(folderName: folderName)
                    } else {
                        fileList(files: files, caseId: caseFolder.id, subfolder: subfolder)
                    }
                }
            } else {
                emptyView(folderName: caseTreeViewModel.selectedSubfolder.rawValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
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
        .sheet(isPresented: $showAddDocument) {
            addDocumentSheet(caseId: caseTreeViewModel.selectedCase!.id, subfolder: caseTreeViewModel.selectedSubfolder)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $pickedImage) { img in
                guard let caseId = caseTreeViewModel.selectedCase?.id,
                      let data = img.jpegData(compressionQuality: 0.8) else { return }
                if caseTreeViewModel.selectedSubfolder == .evidence {
                    let evidenceCount = caseTreeViewModel.files(for: caseId, subfolder: .evidence).count
                    let usage = PremiumUsage(documentCountInCase: 0, evidenceCountInCase: evidenceCount)
                    if !PremiumAccessManager.canAccess(.evidenceUploads, hasFullAccess: subscriptionViewModel.hasFullAccess, usage: usage) {
                        upgradePromptToShow = PremiumAccessManager.upgradePrompt(for: .evidenceUploads)
                        return
                    }
                }
                _ = caseTreeViewModel.addImage(caseId: caseId, subfolder: caseTreeViewModel.selectedSubfolder, name: "Image \(Date().formatted(date: .abbreviated, time: .shortened))", imageData: data)
            }
        }
        .sheet(isPresented: $showFormImagePicker) {
            ImagePicker(image: $pickedImage) { img in
                Task {
                    await importScannedImage(img)
                }
            }
        }
        .fileImporter(
            isPresented: $showFormImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await importDocument(from: url)
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .sheet(item: $upgradePromptToShow) { prompt in
            UpgradePromptSheet(prompt: prompt) { upgradePromptToShow = nil }
        }
        .sheet(item: $autofillSession) { session in
            DocumentAutofillReviewSheet(
                session: Binding(
                    get: { autofillSession ?? session },
                    set: { autofillSession = $0 }
                ),
                onCancel: {
                    autofillSession = nil
                },
                onSave: {
                    Task {
                        await saveCompletedDocument()
                    }
                }
            )
        }
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
        .alert("Document import", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
        .overlay {
            if isProcessingImportedDocument {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    ProgressView("Processing document…")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func header(folderName: String, caseId: UUID, subfolder: CaseSubfolder) -> some View {
        HStack {
            Text(folderName)
                .font(LuxuryTheme.sectionFont(size: 18))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            Menu {
                Button {
                    newDocName = ""
                    newDocContent = ""
                    showAddDocument = true
                } label: {
                    Label("Add document", systemImage: "doc.badge.plus")
                }
                Button {
                    showImagePicker = true
                } label: {
                    Label("Add image", systemImage: "photo.badge.plus")
                }
                Button {
                    showFormImporter = true
                } label: {
                    Label("Import form or PDF", systemImage: "doc.viewfinder")
                }
                Button {
                    showFormImagePicker = true
                } label: {
                    Label("Import scanned image", systemImage: "text.viewfinder")
                }
            } label: {
                AccentOutlinePlusIcon()
            }
        }
        .padding()
    }

    private func addDocumentSheet(caseId: UUID, subfolder: CaseSubfolder) -> some View {
        NavigationView {
            Form {
                TextField("Document name", text: $newDocName)
                TextField("Content (optional)", text: $newDocContent, axis: .vertical)
                    .lineLimit(5...10)
            }
            .navigationTitle("Add document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddDocument = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if subfolder == .evidence {
                            let evidenceCount = caseTreeViewModel.files(for: caseId, subfolder: .evidence).count
                            let usage = PremiumUsage(documentCountInCase: 0, evidenceCountInCase: evidenceCount)
                            if !PremiumAccessManager.canAccess(.evidenceUploads, hasFullAccess: subscriptionViewModel.hasFullAccess, usage: usage) {
                                upgradePromptToShow = PremiumAccessManager.upgradePrompt(for: .evidenceUploads)
                                return
                            }
                        }
                        let name = newDocName.isEmpty ? "Untitled \(Date().formatted(date: .abbreviated, time: .omitted))" : newDocName
                        let file = CaseFile(name: name, type: .note, relativePath: "", content: newDocContent.isEmpty ? nil : newDocContent)
                        caseTreeViewModel.addFile(caseId: caseId, subfolder: subfolder, file: file, content: newDocContent.isEmpty ? nil : newDocContent)
                        if subfolder == .evidence, !newDocContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Task {
                                await workspace.processUploadedEvidenceDocument(caseId: caseId, documentText: newDocContent)
                            }
                        }
                        showAddDocument = false
                    }
                    .disabled(newDocName.isEmpty && newDocContent.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Evidence view: grouped by category (Photos, Documents, Messages, Witness Statements, Videos). Items appear in the folder matching their categorized type.
    @ViewBuilder
    private func evidenceCategorizedContent(files: [CaseFile], caseId: UUID) -> some View {
        let grouped = Dictionary(grouping: files) { file in
            evidenceCategorizationEngine.categorize(fileName: file.name)
        }
        if files.isEmpty {
            emptyView(folderName: "Evidence")
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(evidenceCategoryOrder, id: \.key) { pair in
                        let categoryFiles = grouped[pair.key] ?? []
                        if !categoryFiles.isEmpty {
                            evidenceCategorySection(title: pair.displayName, files: categoryFiles, caseId: caseId)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func evidenceCategorySection(title: String, files: [CaseFile], caseId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: evidenceCategoryIcon(title))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.primary)
                Text(title)
                    .font(LuxuryTheme.sectionFont(size: 16))
                    .foregroundColor(AppColors.textPrimary)
                Text("(\(files.count))")
                    .font(LuxuryTheme.bodyFont(size: 14))
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(.horizontal, 4)

            ForEach(files) { file in
                fileRow(file, caseId: caseId, subfolder: .evidence)
            }
        }
    }

    private func evidenceCategoryIcon(_ displayName: String) -> String {
        switch displayName {
        case "Photos": return "photo.fill"
        case "Documents": return "doc.fill"
        case "Messages": return "message.fill"
        case "Witness Statements": return "person.fill"
        case "Videos": return "video.fill"
        default: return "folder.fill"
        }
    }

    private func emptyView(folderName: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text("No files in \(folderName)")
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text("Add documents or images with the + button. Everything is stored on your device.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileList(files: [CaseFile], caseId: UUID, subfolder: CaseSubfolder) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(files) { file in
                    fileRow(file, caseId: caseId, subfolder: subfolder)
                }
            }
            .padding()
        }
    }

    private func fileRow(_ file: CaseFile, caseId: UUID, subfolder: CaseSubfolder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let tag = file.responseTag {
                Text(tag.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 59/255, green: 130/255, blue: 246/255, opacity: 0.12))
                    .cornerRadius(999)
            }
            HStack {
                Image(systemName: iconName(for: file.type))
                    .foregroundColor(AppColors.textPrimary)
                Text(file.name)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                downloadButton(for: file)
            }
            .padding(12)
            .background(LuxuryTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
            )
            .cornerRadius(10)
            if file.type == .image, caseTreeViewModel.fileExistsOnDisk(file) {
                imagePreview(file)
            } else if let content = file.content, !content.isEmpty {
                Text(content)
                    .font(LuxuryTheme.bodyFont(size: 12))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                Divider().background(LuxuryTheme.cardBorder).padding(.vertical, 4)
            }
        }
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

            if let content = file.content, !content.isEmpty {
                Button {
                    exportPDF(for: file)
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }

                Button {
                    UIPasteboard.general.string = content
                } label: {
                    Label("Copy to clipboard", systemImage: "doc.on.doc")
                }
            }

            Button {
                previewFile(file)
            } label: {
                Label("Preview", systemImage: "eye")
            }

            if file.type == .pdf {
                Button {
                    savePDFPreviewToPhotos(file)
                } label: {
                    Label("Save Preview to Photos", systemImage: "photo")
                }
            }

            Button {
                exportFileOrContent(file)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
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
                moveDestinationMenuItem(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .evidence, fileId: file.id)
                moveDestinationMenuItem(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .documents, fileId: file.id)
                moveDestinationMenuItem(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .response, fileId: file.id)
                moveDestinationMenuItem(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .history, fileId: file.id)
                moveDestinationMenuItem(caseId: caseId, fromSubfolder: subfolder, toSubfolder: .filedDocuments, fileId: file.id)
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

    @ViewBuilder
    private func imagePreview(_ file: CaseFile) -> some View {
        let url = caseTreeViewModel.fileURL(for: file)
        if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func downloadButton(for file: CaseFile) -> some View {
        if caseTreeViewModel.fileExistsOnDisk(file) || (file.content?.isEmpty == false) {
            Button {
                exportFileOrContent(file)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(AppColors.textPrimary)
            }
            .buttonStyle(AppTapButtonStyle())
        }
    }

    private func exportFileOrContent(_ file: CaseFile) {
        let items: [Any]
        if caseTreeViewModel.fileExistsOnDisk(file) {
            items = [caseTreeViewModel.fileURL(for: file)]
        } else if let content = file.content {
            items = [content]
        } else {
            return
        }
        presentShareSheet(items: items)
    }

    private func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }

        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        av.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                guard subscriptionViewModel.hasFullAccess == false else { return }
                NotificationCenter.default.post(name: .contextualMonetizationExport, object: nil)
            }
        }
        root.present(av, animated: true)
    }

    private func previewFile(_ file: CaseFile) {
        if caseTreeViewModel.fileExistsOnDisk(file) {
            previewItem = PreviewFileItem(url: caseTreeViewModel.fileURL(for: file))
        } else if let url = makeTextPDFURL(title: file.name, text: file.content ?? "") {
            previewItem = PreviewFileItem(url: url)
        }
    }

    private func savePDFPreviewToPhotos(_ file: CaseFile) {
        guard caseTreeViewModel.fileExistsOnDisk(file) else { return }
        let url = caseTreeViewModel.fileURL(for: file)
        guard let image = completedDocumentWriter.previewImage(for: url) else {
            importErrorMessage = "A preview image could not be generated for this PDF."
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    private func exportPDF(for file: CaseFile) {
        guard let content = file.content, !content.isEmpty else { return }
        guard let url = makeTextPDFURL(title: file.name, text: content) else { return }
        presentShareSheet(items: [url])
    }

    private func makeTextPDFURL(title: String, text: String) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter (72dpi)
        let margin: CGFloat = 36
        let maxWidth = pageRect.width - (margin * 2)
        let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let lineHeight = font.lineHeight

        func wrapLines(_ text: String) -> [String] {
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            let paragraphs = normalized.components(separatedBy: "\n")
            var lines: [String] = []

            for para in paragraphs {
                let words = para.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                var current = ""
                for word in words {
                    let candidate = current.isEmpty ? word : "\(current) \(word)"
                    let size = (candidate as NSString).size(withAttributes: attributes)
                    if size.width > maxWidth, !current.isEmpty {
                        lines.append(current)
                        current = word
                    } else {
                        current = candidate
                    }
                }
                if !current.isEmpty {
                    lines.append(current)
                }
                // Blank line between paragraphs
                if !para.isEmpty {
                    lines.append("")
                }
            }
            return lines
        }

        let lines = wrapLines(text)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = renderer.pdfData { context in
            var y: CGFloat = margin
            var didDrawHeader = false

            func beginPage() {
                context.beginPage()
                y = margin
                didDrawHeader = false
            }

            beginPage()

            // Title header
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16)
            ]
            let header = "\(title)"
            header.draw(in: CGRect(x: margin, y: y, width: maxWidth, height: 22), withAttributes: headerAttributes)
            y += 30
            didDrawHeader = true

            for line in lines {
                if y + lineHeight > pageRect.height - margin {
                    beginPage()
                    header.draw(in: CGRect(x: margin, y: y, width: maxWidth, height: 22), withAttributes: headerAttributes)
                    y += 30
                    didDrawHeader = true
                }
                NSString(string: line).draw(in: CGRect(x: margin, y: y, width: maxWidth, height: lineHeight), withAttributes: attributes)
                y += lineHeight
            }
            _ = didDrawHeader
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketLawyer_\(UUID().uuidString).pdf")
        do {
            try pdfData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func moveDestinationMenuItem(
        caseId: UUID,
        fromSubfolder: CaseSubfolder,
        toSubfolder: CaseSubfolder,
        fileId: UUID
    ) -> some View {
        Button {
            caseTreeViewModel.moveFile(caseId: caseId, fromSubfolder: fromSubfolder, toSubfolder: toSubfolder, fileId: fileId)
        } label: {
            Text(toSubfolder.rawValue)
        }
    }

    private func iconName(for type: CaseFileType) -> String {
        switch type {
        case .pdf: return "doc.fill"
        case .docx: return "doc.text.fill"
        case .image: return "photo.fill"
        case .audio: return "mic.fill"
        case .note: return "note.text"
        default: return "doc.fill"
        }
    }

    private func importDocument(from url: URL) async {
        guard let caseFolder = caseTreeViewModel.selectedCase else {
            importErrorMessage = "Select a case or research folder before importing a document."
            return
        }

        isProcessingImportedDocument = true
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            isProcessingImportedDocument = false
        }

        do {
            let data = try Data(contentsOf: url)
            try await prepareAutofillSession(
                caseFolder: caseFolder,
                fileName: url.lastPathComponent,
                originalData: data
            )
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func importScannedImage(_ image: UIImage) async {
        guard let caseFolder = caseTreeViewModel.selectedCase else {
            importErrorMessage = "Select a case or research folder before importing a scan."
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            importErrorMessage = "The scanned image could not be prepared."
            return
        }

        isProcessingImportedDocument = true
        defer { isProcessingImportedDocument = false }

        do {
            let name = "Scanned Form \(Date().formatted(date: .abbreviated, time: .shortened)).jpg"
            try await prepareAutofillSession(caseFolder: caseFolder, fileName: name, originalData: data)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func prepareAutofillSession(caseFolder: CaseFolder, fileName: String, originalData: Data) async throws {
        let processed = try await documentProcessingService.processDocument(data: originalData, fileName: fileName)
        let state = workspace.state(for: caseFolder.id)
        let draft = documentAutofillService.prepareDraft(for: processed, caseState: state, caseFolder: caseFolder)
        autofillSession = DocumentAutofillReviewSession(
            caseId: caseFolder.id,
            originalData: originalData,
            processed: processed,
            draft: draft
        )
    }

    private func saveCompletedDocument() async {
        guard let session = autofillSession else { return }
        isProcessingImportedDocument = true
        defer { isProcessingImportedDocument = false }

        do {
            let originalName = session.processed.originalFileName

            _ = caseTreeViewModel.addBinaryFile(
                caseId: session.caseId,
                subfolder: .documents,
                name: originalName,
                type: session.processed.originalFileType,
                data: session.originalData,
                extractedText: session.processed.extractedText,
                responseTag: .note
            )

            let completedURL = try completedDocumentWriter.makeCompletedPDF(
                originalData: session.originalData,
                processed: session.processed,
                draft: session.draft
            )
            let completedData = try Data(contentsOf: completedURL)
            let completedName = completedDocumentWriter.completedFileName(for: originalName)

            caseTreeViewModel.setSubfolderHidden(caseId: session.caseId, subfolder: .filedDocuments, hidden: false)
            guard let completedFile = caseTreeViewModel.addBinaryFile(
                caseId: session.caseId,
                subfolder: .filedDocuments,
                name: completedName,
                type: .pdf,
                data: completedData,
                extractedText: completedDocumentWriter.summaryText(for: session.draft),
                responseTag: .draft
            ) else {
                throw NSError(domain: "DocumentListView", code: 1, userInfo: [NSLocalizedDescriptionKey: "The completed document could not be saved into the case."])
            }

            caseTreeViewModel.addTimelineEvent(
                TimelineEvent(
                    kind: .response,
                    title: "Completed form saved",
                    summary: completedName,
                    createdAt: Date(),
                    documentId: completedFile.id,
                    subfolder: .filedDocuments
                ),
                caseId: session.caseId
            )

            caseTreeViewModel.selectedSubfolder = .filedDocuments
            caseTreeViewModel.selectedFileId = completedFile.id
            previewItem = PreviewFileItem(url: caseTreeViewModel.fileURL(for: completedFile))
            autofillSession = nil
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

private struct PreviewFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DocumentAutofillReviewSession: Identifiable {
    let id = UUID()
    let caseId: UUID
    let originalData: Data
    let processed: ProcessedDocument
    var draft: DocumentAutofillDraft
}

private struct DocumentAutofillReviewSheet: View {
    @Binding var session: DocumentAutofillReviewSession
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Form") {
                    Text(session.processed.originalFileName)
                    Text(session.draft.summary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Fields") {
                    ForEach($session.draft.fields) { $field in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(field.label)
                                Spacer()
                                Text(field.confidence.rawValue)
                                    .font(.caption)
                                    .foregroundColor(field.confidence == .missing ? .red : .secondary)
                            }
                            TextField("Needs review", text: $field.value, axis: .vertical)
                                .lineLimit(1...3)
                            Text(field.source)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Review Autofill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}


// MARK: - Image picker (PhotosUI)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                DispatchQueue.main.async {
                    if let img = obj as? UIImage {
                        self?.parent.image = img
                        self?.parent.onPick(img)
                    }
                }
            }
        }
    }
}
