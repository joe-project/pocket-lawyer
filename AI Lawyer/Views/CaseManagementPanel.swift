import SwiftUI

struct CaseManagementPanel: View {
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var learningViewModel: LearningViewModel
    @Binding var showLearning: Bool
    @State private var searchText = ""
    @State private var renamingCase: CaseFolder?
    @State private var renameText: String = ""

    private var caseTreeViewModel: CaseTreeViewModel { workspace.caseTreeViewModel }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if workspace.isInvitedParticipantMode {
                    invitedParticipantBanner
                }
                searchSection
                casesSection
                Divider()
                    .background(LuxuryTheme.navBarBorder)
                    .padding(.horizontal, 8)
                bottomSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 600)
        }
        .scrollBounceBehavior(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.card)
        .sheet(item: $renamingCase) { folder in
            NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rename case")
                        .font(LuxuryTheme.sectionFont(size: 18))
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Case name", text: $renameText)
                        .font(LuxuryTheme.bodyFont(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                        .padding(10)
                        .background(LuxuryTheme.surfaceCard)
                        .cornerRadius(10)

                    Text("Give this case a name that makes sense to you. Only you can see it.")
                        .font(LuxuryTheme.bodyFont(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(20)
                .background(AppColors.background)
                .navigationTitle("Rename Case")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { renamingCase = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            caseTreeViewModel.renameCase(id: folder.id, to: renameText)
                            renamingCase = nil
                        }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var invitedParticipantBanner: some View {
        Text("You're contributing as an invited participant. You can upload evidence or record statements for this case.")
            .font(LuxuryTheme.bodyFont(size: 12))
            .foregroundColor(AppColors.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LuxuryTheme.surfaceCard.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: - Top: Search (text only — no decorative icon)
    private var searchSection: some View {
        TextField("Search cases", text: $searchText)
            .font(LuxuryTheme.bodyFont(size: 14))
            .foregroundColor(AppColors.textPrimary)
            .padding(10)
            .background(LuxuryTheme.surfaceCard)
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    // MARK: - Second: Cases list
    private var casesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cases")
                .font(LuxuryTheme.sectionFont(size: 12))
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 226/255, green: 232/255, blue: 240/255, opacity: 0.65))

            let filtered = filteredCases
            ForEach(filtered) { folder in
                Button {
                    workspace.selectCase(byFolder: folder)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(AppTypography.body)
                            .foregroundColor(
                                caseTreeViewModel.selectedCase?.id == folder.id
                                    ? AppColors.primary
                                    : AppColors.textSecondary
                            )
                            .frame(width: 16, alignment: .center)
                        Text(folder.title)
                            .font(LuxuryTheme.bodyFont(size: 14))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.6)
                        .onEnded { _ in
                            renamingCase = folder
                            renameText = folder.title
                        }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    caseTreeViewModel.selectedCase?.id == folder.id
                        ? Color(red: 59/255, green: 130/255, blue: 246/255, opacity: 0.12)
                        : Color.clear
                )
                .cornerRadius(10)
            }
        }
    }

    private var filteredCases: [CaseFolder] {
        var list = caseTreeViewModel.cases
        if workspace.isInvitedParticipantMode, let id = workspace.invitedCaseId {
            list = list.filter { $0.id == id }
        }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if term.isEmpty { return list }
        return list.filter { $0.title.lowercased().contains(term) }
    }

    // MARK: - Bottom: learning links (book, doc.text, clock only)
    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            bottomSectionRow(systemName: "book", title: "Knowledge") {
                showLearning = true
            }
            bottomSectionRow(systemName: "doc.text", title: "Legal Guides") {
                showLearning = true
            }
            bottomSectionRow(systemName: "clock", title: "Learn Law") {
                showLearning = true
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func bottomSectionRow(systemName: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(LuxuryTheme.bodyFont(size: 14))
                    .foregroundColor(AppColors.textPrimary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
