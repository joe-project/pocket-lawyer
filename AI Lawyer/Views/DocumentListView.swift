import SwiftUI
import PhotosUI

struct DocumentListView: View {
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @State private var showAddDocument = false
    @State private var showImagePicker = false
    @State private var pickedImage: UIImage?
    @State private var newDocName = ""
    @State private var newDocContent = ""

    var body: some View {
        Group {
            if let caseFolder = caseTreeViewModel.selectedCase {
                let subfolder = caseTreeViewModel.selectedSubfolder
                let folderName = caseTreeViewModel.folderDisplayName(caseId: caseFolder.id, subfolder: subfolder)
                let files = caseTreeViewModel.files(for: caseFolder.id, subfolder: subfolder)
                VStack(alignment: .leading, spacing: 0) {
                    header(folderName: folderName, caseId: caseFolder.id, subfolder: subfolder)
                    if files.isEmpty {
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
        .background(Color("BackgroundNavy").opacity(0.98))
        .sheet(isPresented: $showAddDocument) {
            addDocumentSheet(caseId: caseTreeViewModel.selectedCase!.id, subfolder: caseTreeViewModel.selectedSubfolder)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $pickedImage) { img in
                if let data = img.jpegData(compressionQuality: 0.8), let caseId = caseTreeViewModel.selectedCase?.id {
                    _ = caseTreeViewModel.addImage(caseId: caseId, subfolder: caseTreeViewModel.selectedSubfolder, name: "Image \(Date().formatted(date: .abbreviated, time: .shortened))", imageData: data)
                }
            }
        }
    }

    private func header(folderName: String, caseId: UUID, subfolder: CaseSubfolder) -> some View {
        HStack {
            Text(folderName)
                .font(.headline)
                .foregroundColor(.white)
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
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color("GoldAccent"))
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
                        let name = newDocName.isEmpty ? "Untitled \(Date().formatted(date: .abbreviated, time: .omitted))" : newDocName
                        let file = CaseFile(name: name, type: .note, relativePath: "", content: newDocContent.isEmpty ? nil : newDocContent)
                        caseTreeViewModel.addFile(caseId: caseId, subfolder: subfolder, file: file, content: newDocContent.isEmpty ? nil : newDocContent)
                        showAddDocument = false
                    }
                    .disabled(newDocName.isEmpty && newDocContent.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func emptyView(folderName: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(Color("GoldAccent").opacity(0.7))
            Text("No files in \(folderName)")
                .font(.headline)
                .foregroundColor(.white)
            Text("Add documents or images with the + button. Everything is stored on your device.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
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
            HStack {
                Image(systemName: iconName(for: file.type))
                    .foregroundColor(Color("GoldAccent"))
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                Spacer()
                downloadButton(for: file)
            }
            .padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
            if file.type == .image, caseTreeViewModel.fileExistsOnDisk(file) {
                imagePreview(file)
            } else if let content = file.content, !content.isEmpty {
                Text(content)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                Divider().background(Color.white.opacity(0.2)).padding(.vertical, 4)
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
        if caseTreeViewModel.fileExistsOnDisk(file) {
            ShareLink(item: caseTreeViewModel.fileURL(for: file)) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(Color("GoldAccent"))
            }
        } else if let content = file.content {
            ShareLink(item: content, subject: Text(file.name)) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(Color("GoldAccent"))
            }
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
