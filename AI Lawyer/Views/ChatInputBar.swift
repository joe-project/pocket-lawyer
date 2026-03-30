import SwiftUI
import UniformTypeIdentifiers

/// Bottom chat strip styled closer to mobile ChatGPT while keeping Pocket Lawyer colors.
struct ChatInputBar: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var voiceRecorder: VoiceRecorder
    @Binding var showFileImporter: Bool

    @AppStorage("isDarkMode") private var isDarkMode = true

    private var barFill: Color {
        isDarkMode ? Color(red: 30/255, green: 30/255, blue: 32/255) : Color(red: 245/255, green: 245/255, blue: 247/255)
    }

    private var iconTint: Color {
        isDarkMode ? Color.white.opacity(0.88) : .black
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showFileImporter = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconTint)
                        .frame(width: 34, height: 34)
                    if !chatViewModel.pendingAttachments.isEmpty {
                        Text("\(chatViewModel.pendingAttachments.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(Color.red.opacity(0.9)))
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(chatViewModel.isSending)

            TextField("Describe what happened...", text: $chatViewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(isDarkMode ? .white : .black)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1...4)

            Button {
                Task {
                    if voiceRecorder.isRecording {
                        let text = await voiceRecorder.stopRecordingAndTranscribe()
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            await MainActor.run { chatViewModel.sendText(trimmed) }
                        }
                    } else {
                        _ = await voiceRecorder.startRecording()
                    }
                }
            } label: {
                Image(systemName: voiceRecorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(voiceRecorder.isRecording ? Color.red : iconTint)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(chatViewModel.isSending)

            Button {
                chatViewModel.sendCurrentMessage()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(chatViewModel.canSend ? .white : AppColors.textSecondary.opacity(0.45))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(chatViewModel.canSend ? AppColors.brandPurple.opacity(0.85) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!chatViewModel.canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(barFill.opacity(isDarkMode ? 0.98 : 0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColors.brandPurple.opacity(0.18), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(isDarkMode ? 0.4 : 0.1),
            radius: 10,
            y: 4
        )
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
        .alert("Chat error", isPresented: Binding(
            get: { chatViewModel.errorMessage != nil },
            set: { if !$0 { chatViewModel.errorMessage = nil } }
        )) {
            Button("OK") { chatViewModel.errorMessage = nil }
        } message: {
            Text(chatViewModel.errorMessage ?? "")
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
        Task { @MainActor in
            chatViewModel.addAttachment(name: name, content: content)
        }
    }
}
