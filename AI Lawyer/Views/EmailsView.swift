import SwiftUI

struct EmailsView: View {
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @EnvironmentObject var caseManager: CaseManager
    @State private var showGenerateSheet = false
    @State private var showEditSheet = false
    @State private var draftToEdit: EmailDraft?
    @State private var editSubject = ""
    @State private var editBody = ""
    @State private var editRecipient = ""
    @State private var isGenerating = false
    @State private var generateError: String?

    private let emailDraftEngine = EmailDraftEngine()
    fileprivate static let emailTypes = ["Demand Letter", "Follow-up", "Introduction", "Settlement", "Discovery Request", "Other"]

    var body: some View {
        Group {
            if let caseFolder = caseTreeViewModel.selectedCase {
                let drafts = caseTreeViewModel.emailDrafts(for: caseFolder.id)
                VStack(alignment: .leading, spacing: 0) {
                    header(caseName: caseFolder.title)
                    if drafts.isEmpty {
                        emptyView(caseFolder: caseFolder)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(drafts) { draft in
                                    emailDraftRow(draft: draft)
                                }
                            }
                            .padding()
                        }
                    }
                }
            } else {
                emptyStateNoCase
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .sheet(isPresented: $showGenerateSheet) {
            generateSheet(caseFolder: caseTreeViewModel.selectedCase!)
        }
        .sheet(isPresented: $showEditSheet) {
            if let draft = draftToEdit {
                editSheet(draft: draft)
            }
        }
        .alert("Email generation failed", isPresented: Binding(
            get: { generateError != nil },
            set: { if !$0 { generateError = nil } }
        )) {
            Button("OK") { generateError = nil }
        } message: {
            Text(generateError ?? "")
        }
    }

    private func header(caseName: String) -> some View {
        HStack {
            Text("Emails")
                .font(LuxuryTheme.sectionFont(size: 18))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            Button {
                showGenerateSheet = true
            } label: {
                HStack(spacing: 8) {
                    AccentOutlinePlusIcon(diameter: 28)
                    Text("Generate")
                        .font(LuxuryTheme.bodyFont(size: 14))
                        .foregroundColor(AppColors.primary)
                }
            }
        }
        .padding()
    }

    private func emptyView(caseFolder: CaseFolder) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text("No email drafts yet")
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text("Tap Generate to create a professional legal email from your case analysis. Drafts are stored here only and are never sent automatically.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Generate email") {
                showGenerateSheet = true
            }
            .buttonStyle(AppButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateNoCase: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text("Select a case")
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text("Select a case from the sidebar to view and generate email drafts.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emailDraftRow(draft: EmailDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(draft.subject)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(draft.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(LuxuryTheme.bodyFont(size: 11))
                    .foregroundColor(AppColors.textPrimary)
            }
            if let recipient = draft.suggestedRecipient, !recipient.isEmpty {
                Text("To: \(recipient)")
                    .font(LuxuryTheme.bodyFont(size: 12))
                    .foregroundColor(AppColors.textPrimary)
            }
            Text(draft.body)
                .font(LuxuryTheme.bodyFont(size: 12))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(3)
            HStack(spacing: 12) {
                Button("Copy") {
                    UIPasteboard.general.string = "Subject: \(draft.subject)\n\n\(draft.body)"
                }
                .font(LuxuryTheme.bodyFont(size: 13))
                .foregroundColor(AppColors.textPrimary)
                ShareLink(item: "Subject: \(draft.subject)\n\n\(draft.body)", subject: Text(draft.subject)) {
                    Text("Export")
                        .font(LuxuryTheme.bodyFont(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                }
                Spacer()
                Button("Edit") {
                    draftToEdit = draft
                    editSubject = draft.subject
                    editBody = draft.body
                    editRecipient = draft.suggestedRecipient ?? ""
                    showEditSheet = true
                }
                .font(LuxuryTheme.bodyFont(size: 13))
                .foregroundColor(AppColors.textPrimary)
            }
        }
        .padding(12)
        .background(LuxuryTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func generateSheet(caseFolder: CaseFolder) -> some View {
        GenerateEmailSheet(
            caseFolder: caseFolder,
            caseManager: caseManager,
            caseTreeViewModel: caseTreeViewModel,
            emailDraftEngine: emailDraftEngine,
            isGenerating: $isGenerating,
            generateError: $generateError,
            onDismiss: { showGenerateSheet = false }
        )
    }

    private func editSheet(draft: EmailDraft) -> some View {
        EditEmailDraftSheet(
            draft: draft,
            caseTreeViewModel: caseTreeViewModel,
            subject: $editSubject,
            bodyText: $editBody,
            recipient: $editRecipient,
            onDismiss: {
                draftToEdit = nil
                showEditSheet = false
            }
        )
    }
}

// MARK: - Generate email sheet
private struct GenerateEmailSheet: View {
    let caseFolder: CaseFolder
    @ObservedObject var caseManager: CaseManager
    @ObservedObject var caseTreeViewModel: CaseTreeViewModel
    let emailDraftEngine: EmailDraftEngine
    @Binding var isGenerating: Bool
    @Binding var generateError: String?
    let onDismiss: () -> Void

    @State private var selectedType = "Demand Letter"

    var body: some View {
        NavigationView {
            Form {
                Section("Email type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(EmailsView.emailTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    Text("Drafts are stored in the case and are never sent automatically. You can copy, export, or edit them.")
                        .font(LuxuryTheme.bodyFont(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .navigationTitle("Generate Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        generateDraft()
                    }
                    .disabled(isGenerating)
                }
            }
        }
    }

    private func generateDraft() {
        guard let analysis = caseManager.getCase(byId: caseFolder.id)?.analysis else {
            generateError = "No case analysis yet. Use Chat to describe your case first."
            return
        }
        isGenerating = true
        generateError = nil
        Task {
            do {
                let draft = try await emailDraftEngine.generateEmailDraft(caseAnalysis: analysis, emailType: selectedType)
                await MainActor.run {
                    caseTreeViewModel.addEmailDraft(caseId: caseFolder.id, draft: draft)
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    generateError = error.localizedDescription
                }
            }
            await MainActor.run { isGenerating = false }
        }
    }
}

// MARK: - Edit email draft sheet
private struct EditEmailDraftSheet: View {
    let draft: EmailDraft
    @ObservedObject var caseTreeViewModel: CaseTreeViewModel
    @Binding var subject: String
    @Binding var bodyText: String
    @Binding var recipient: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Subject") {
                    TextField("Subject", text: $subject)
                }
                Section("Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                }
                Section("Suggested recipient") {
                    TextField("Optional", text: $recipient)
                }
            }
            .navigationTitle("Edit Email Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let caseId = caseTreeViewModel.selectedCase?.id else { return }
                        caseTreeViewModel.updateEmailDraft(
                            caseId: caseId,
                            draftId: draft.id,
                            subject: subject,
                            body: bodyText,
                            suggestedRecipient: recipient.isEmpty ? nil : recipient
                        )
                        onDismiss()
                    }
                }
            }
        }
    }
}

