import SwiftUI
import PhotosUI
import UIKit

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
    @State private var pickedImage: UIImage?
    @State private var newDocName = ""
    @State private var newDocContent = ""
    @State private var upgradePromptToShow: UpgradePrompt?
    private let evidenceCategorizationEngine = EvidenceCategorizationEngine()

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
        .sheet(item: $upgradePromptToShow) { prompt in
            UpgradePromptSheet(prompt: prompt) { upgradePromptToShow = nil }
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
