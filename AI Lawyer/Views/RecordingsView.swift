import SwiftUI
import UIKit

struct RecordingsView: View {
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @State private var expandedSubfolders: Set<RecordingSubfolder> = Set(RecordingSubfolder.allCases)
    @State private var showAddSheet = false
    @State private var addToSubfolder: RecordingSubfolder = .voiceStories
    @State private var newRecordingName = ""

    var body: some View {
        Group {
            if let caseFolder = caseTreeViewModel.selectedCase {
                let allRecordings = caseTreeViewModel.files(for: caseFolder.id, subfolder: .recordings)
                let filesForCase = allRecordings.filter { $0.caseId == caseFolder.id || $0.caseId == nil }
                VStack(alignment: .leading, spacing: 0) {
                    header(caseName: caseFolder.title)
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(RecordingSubfolder.allCases) { subfolder in
                                let filesInFolder = filesForCase.filter { $0.recordingSubfolder == subfolder || ($0.recordingSubfolder == nil && subfolder == .voiceStories) }
                                DisclosureGroup(isExpanded: Binding(
                                    get: { expandedSubfolders.contains(subfolder) },
                                    set: { if $0 { expandedSubfolders.insert(subfolder) } else { expandedSubfolders.remove(subfolder) } }
                                )) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(filesInFolder) { file in
                                            recordingRow(file: file, caseName: caseFolder.title)
                                        }
                                        addRecordingButton(caseId: caseFolder.id, subfolder: subfolder)
                                    }
                                    .padding(.leading, 8)
                                    .padding(.vertical, 6)
                                } label: {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .font(AppTypography.body)
                                            .foregroundColor(AppColors.textPrimary)
                                        Text(subfolder.rawValue)
                                            .font(LuxuryTheme.bodyFont(size: 15))
                                            .fontWeight(.medium)
                                            .foregroundColor(AppColors.textPrimary)
                                        Text("\(filesInFolder.count)")
                                            .font(LuxuryTheme.bodyFont(size: 12))
                                            .foregroundColor(AppColors.textPrimary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(LuxuryTheme.surfaceCard)
                                            .cornerRadius(6)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 4)
                                }
                                .accentColor(AppColors.textPrimary)
                            }
                        }
                        .padding()
                    }
                }
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .sheet(isPresented: $showAddSheet) {
            addRecordingSheet(caseId: caseTreeViewModel.selectedCase!.id)
        }
    }

    private func header(caseName: String) -> some View {
        Text(caseTreeViewModel.folderDisplayName(caseId: caseTreeViewModel.selectedCase!.id, subfolder: .recordings))
            .font(LuxuryTheme.sectionFont(size: 18))
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text("No recordings yet")
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text("Expand a folder below and tap \"Add recording\" to add one. Voice recordings from the mic can also be saved here when you record with a case selected.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addRecordingButton(caseId: UUID, subfolder: RecordingSubfolder) -> some View {
        Button {
            addToSubfolder = subfolder
            newRecordingName = ""
            showAddSheet = true
        } label: {
            HStack(spacing: 8) {
                AccentOutlinePlusIcon(diameter: 28)
                Text("Add recording")
                    .font(LuxuryTheme.bodyFont(size: 14))
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(AppColors.secondaryButton)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func addRecordingSheet(caseId: UUID) -> some View {
        NavigationView {
            Form {
                Section("Folder") {
                    Picker("Save to", selection: $addToSubfolder) {
                        ForEach(RecordingSubfolder.allCases, id: \.self) { sub in
                            Text(sub.rawValue).tag(sub)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Name") {
                    TextField("Recording name", text: $newRecordingName)
                }
            }
            .navigationTitle("Add Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        _ = caseTreeViewModel.addRecording(caseId: caseId, recordingSubfolder: addToSubfolder, name: newRecordingName.trimmingCharacters(in: .whitespacesAndNewlines))
                        showAddSheet = false
                    }
                }
            }
        }
    }

    private func recordingRow(file: CaseFile, caseName: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.fill")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.name)
                        .font(LuxuryTheme.bodyFont(size: 15))
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if caseTreeViewModel.fileExistsOnDisk(file) {
                        Button {
                            exportRecording(file)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .buttonStyle(AppTapButtonStyle())
                    }
                }

                if let transcript = file.content, !transcript.isEmpty {
                    Text(transcript)
                        .font(LuxuryTheme.bodyFont(size: 12))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(file.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(LuxuryTheme.bodyFont(size: 11))
                        .foregroundColor(AppColors.textPrimary)
                    Text("·")
                        .font(LuxuryTheme.bodyFont(size: 11))
                        .foregroundColor(AppColors.textPrimary)
                    Text(formattedDuration(file.durationSeconds))
                        .font(LuxuryTheme.bodyFont(size: 11))
                        .foregroundColor(AppColors.textPrimary)
                    Text("·")
                        .font(LuxuryTheme.bodyFont(size: 11))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Case: \(caseName)")
                        .font(LuxuryTheme.bodyFont(size: 11))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(LuxuryTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func exportRecording(_ file: CaseFile) {
        guard caseTreeViewModel.fileExistsOnDisk(file) else { return }
        let items: [Any] = [caseTreeViewModel.fileURL(for: file)]

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

    private func formattedDuration(_ seconds: Int?) -> String {
        guard let sec = seconds, sec >= 0 else { return "—" }
        let m = sec / 60
        let s = sec % 60
        if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }
}
