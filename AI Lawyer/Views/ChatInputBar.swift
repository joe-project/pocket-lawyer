import SwiftUI
import UniformTypeIdentifiers

/// Bottom chat strip: pill input only (theme toggle lives on main content).
struct ChatInputBar: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var voiceRecorder: VoiceRecorder
    @Binding var showFileImporter: Bool

    @AppStorage("isDarkMode") private var isDarkMode = true

    private var cardBackground: Color {
        isDarkMode ? Color.black.opacity(0.82) : Color(white: 0.9)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                inputPill
                    .frame(maxWidth: 700)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
        .background(Color.black)
    }

    private var inputPill: some View {
        unifiedInputBar(
            inputText: $chatViewModel.inputText,
            chatViewModel: chatViewModel,
            voiceRecorder: voiceRecorder,
            showFileImporter: $showFileImporter
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
        .background(
            Capsule(style: .continuous)
                .fill(cardBackground)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(red: 120/255, green: 80/255, blue: 1.0, opacity: 0.6), lineWidth: 1.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .text, .image, .movie, .video, .content],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result, chatViewModel: chatViewModel)
        }
        .alert("Voice input", isPresented: Binding(
            get: { voiceRecorder.errorMessage != nil },
            set: { if !$0 { voiceRecorder.errorMessage = nil } }
        )) {
            Button("OK") { voiceRecorder.errorMessage = nil }
        } message: {
            Text(voiceRecorder.errorMessage ?? "")
        }
    }
}

// MARK: - Unified AI input bar

private func unifiedInputBar(
    inputText: Binding<String>,
    chatViewModel: ChatViewModel,
    voiceRecorder: VoiceRecorder,
    showFileImporter: Binding<Bool>
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        if !chatViewModel.pendingAttachments.isEmpty {
            HStack(spacing: 6) {
                ForEach(chatViewModel.pendingAttachments) { att in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(AppTypography.body)
                        Text(att.name)
                            .font(LuxuryTheme.bodyFont(size: 12))
                            .lineLimit(1)
                        Text("Attached")
                            .font(LuxuryTheme.bodyFont(size: 11))
                            .foregroundColor(AppColors.textPrimary)
                        Button {
                            chatViewModel.removePendingAttachment(id: att.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.body)
                        }
                        .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LuxuryTheme.surfaceCard)
                    .cornerRadius(8)
                }
            }
        }
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                showFileImporter.wrappedValue = true
            } label: {
                AccentOutlinePlusIcon()
            }
            .disabled(chatViewModel.isSending)

            TextField("Describe what happened or record your story...", text: inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(LuxuryTheme.bodyFont(size: 15))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LuxuryTheme.surfaceCard)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                )
                .lineLimit(1...4)

            Button {
                Task {
                    if voiceRecorder.isRecording {
                        let text = await voiceRecorder.stopRecordingAndTranscribe()
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            await MainActor.run {
                                chatViewModel.sendText(trimmed)
                            }
                        }
                    } else {
                        _ = await voiceRecorder.startRecording()
                    }
                }
            } label: {
                Image(systemName: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundColor(voiceRecorder.isRecording ? .red : AppColors.textPrimary)
            }
            .disabled(chatViewModel.isSending)

            Button(action: { chatViewModel.sendCurrentMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(chatViewModel.canSend ? AppColors.primary : AppColors.textSecondary.opacity(0.45))
            }
            .disabled(!chatViewModel.canSend)
        }
    }
}

private func handleFileImport(result: Result<[URL], Error>, chatViewModel: ChatViewModel) {
    guard case .success(let urls) = result else { return }
    for url in urls {
        guard url.startAccessingSecurityScopedResource() else { continue }
        defer { url.stopAccessingSecurityScopedResource() }
        let name = url.lastPathComponent
        let content: String
        if let data = try? Data(contentsOf: url),
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            content = str.count > 15000 ? String(str.prefix(15000)) + "…" : str
        } else {
            content = ""
        }
        let finalName = name
        let finalContent = content
        Task { @MainActor in
            chatViewModel.addAttachment(name: finalName, content: finalContent)
        }
    }
}
