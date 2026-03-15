import SwiftUI

struct CaseManagementPanel: View {
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @EnvironmentObject var learningViewModel: LearningViewModel
    @Binding var showLearning: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                casesList
                if caseTreeViewModel.selectedCase != nil {
                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.horizontal, 8)
                    folderTreeSection
                }
                learningRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 600)
        }
        .scrollBounceBehavior(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color("BackgroundNavy"))
    }

    private var casesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CaseCategory.allCases, id: \.self) { category in
                let casesInCategory = caseTreeViewModel.cases.filter { $0.category == category }
                if !casesInCategory.isEmpty {
                    Text(category.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color("SidebarHeadingBlue"))

                    ForEach(casesInCategory) { folder in
                        Button(folder.title) {
                            caseTreeViewModel.selectedCase = folder
                        }
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            caseTreeViewModel.selectedCase?.id == folder.id
                                ? Color("GoldAccent").opacity(0.3)
                                : Color.clear
                        )
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var folderTreeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Folders")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color("SidebarHeadingBlue"))

            ForEach(CaseSubfolder.allCases, id: \.self) { subfolder in
                FolderRowView(
                    subfolder: subfolder,
                    displayName: caseTreeViewModel.selectedCase.flatMap { caseTreeViewModel.folderDisplayName(caseId: $0.id, subfolder: subfolder) } ?? subfolder.rawValue,
                    isSelected: caseTreeViewModel.selectedSubfolder == subfolder,
                    onSelect: { caseTreeViewModel.selectedSubfolder = subfolder },
                    onRename: caseTreeViewModel.selectedCase.flatMap { folder in
                        { newName in caseTreeViewModel.setFolderDisplayName(caseId: folder.id, subfolder: subfolder, name: newName) }
                    }
                )
            }
        }
        .padding(.bottom, 8)
    }

    private var learningRow: some View {
        Button {
            showLearning = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.subheadline)
                Text("Learning")
                    .font(.subheadline)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(.white.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

// MARK: - Folder row with optional rename
private struct FolderRowView: View {
    let subfolder: CaseSubfolder
    let displayName: String
    let isSelected: Bool
    let onSelect: () -> Void
    var onRename: ((String) -> Void)?

    @State private var showRenameAlert = false
    @State private var renameText = ""

    var body: some View {
        Button(action: onSelect) {
            Text(displayName)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isSelected ? Color("GoldAccent") : .white.opacity(0.9))
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            if onRename != nil {
                Button("Rename folder") {
                    renameText = displayName
                    showRenameAlert = true
                }
            }
        }
        .alert("Rename folder", isPresented: $showRenameAlert) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                onRename?(renameText)
            }
        } message: {
            Text("Enter a new name for this folder.")
        }
    }
}
