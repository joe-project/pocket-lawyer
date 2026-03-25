import SwiftUI

/// Finder-like dual-pane main panel: top active case/file, middle chat + documents.
struct LegalOSMainPanelView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel

    var body: some View {
        let selectionTransition: AnyTransition = .opacity.combined(with: .move(edge: .bottom))
        let selectionAnimDuration: Double = 0.18

        VStack(spacing: 20) {
            activeCaseHeader
                .id(caseTreeViewModel.selectedFileId?.uuidString ?? "none")
                .transition(selectionTransition)
                .animation(.easeInOut(duration: selectionAnimDuration), value: caseTreeViewModel.selectedFileId?.uuidString ?? "none")

            GeometryReader { geo in
                let wide = geo.size.width >= 900
                if wide {
                    HStack(alignment: .top, spacing: 20) {
                        LegalOSChatPanel(chatViewModel: chatViewModel)
                            .id(caseTreeViewModel.selectedFileId?.uuidString ?? "none")
                            .frame(width: geo.size.width * 0.44)

                        LegalOSDocumentPanel()
                            .frame(width: geo.size.width * 0.56)
                            .frame(height: geo.size.height * 0.52, alignment: .top)
                    }
                } else {
                    VStack(spacing: 20) {
                        LegalOSChatPanel(chatViewModel: chatViewModel)
                            .id(caseTreeViewModel.selectedFileId?.uuidString ?? "none")
                        LegalOSDocumentPanel()
                            .frame(height: geo.size.height * 0.46, alignment: .top)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    private var activeCaseHeader: some View {
        let caseTitle = caseTreeViewModel.selectedCase?.title ?? "-"
        return VStack(alignment: .leading, spacing: 8) {
            Text("Case: \(caseTitle)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)

            if let file = caseTreeViewModel.selectedFile(),
               let content = file.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                Text(content.count > 220 ? String(content.prefix(220)) + "…" : content)
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
            } else {
                Text("Chat and generated documents are tied to your selected case folder.")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(LuxuryTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(colorSchemeStrokeOpacity), lineWidth: 1)
        )
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    private var colorSchemeStrokeOpacity: Double {
        // Keep simple: subtle header border like #FFFFFF @ 0.06 for dark,
        // and the same token works as a “quiet” border in light.
        return 0.06
    }
}

private struct LegalOSChatPanel: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @EnvironmentObject var conversationManager: ConversationManager

    var body: some View {
        let caseId = caseTreeViewModel.selectedCase?.id
        let fileId = caseTreeViewModel.selectedFileId
        let messages = chatViewModel.messages.filter { msg in
            guard let caseId else {
                return msg.caseId == nil && msg.fileId == nil
            }
            if let fileId {
                return msg.caseId == caseId && msg.fileId == fileId
            } else {
                return msg.caseId == caseId && msg.fileId == nil
            }
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("DEBUG: message count = \(messages.count)")
                .foregroundColor(.red)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty {
                        Text("No visible messages")
                            .foregroundColor(.white)
                    } else {
                        ForEach(messages) { message in
                            Text(message.content)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue.opacity(0.3))
                        }
                    }

                    if conversationManager.offeringResumeIntake {
                        Button {
                            chatViewModel.resumeIntake()
                        } label: {
                            Text("Resume intake")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppButtonStyle())
                        .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green.opacity(0.2))
            .border(Color.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .onChange(of: chatViewModel.messages.count) { _, count in
            print("UI RECEIVED MESSAGES:", count)
        }
    }

    private func chatBubble(_ message: ChatMessage, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .leading : .trailing, spacing: 8) {
            if let tag = message.responseTag, !isUser {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text(tag.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 59/255, green: 130/255, blue: 246/255, opacity: 0.12))
                        .cornerRadius(999)
                }
            }

            Text(message.text)
                .font(LuxuryTheme.bodyFont(size: 15))
                .frame(maxWidth: 380, alignment: isUser ? .leading : .trailing)
        }
        .padding(12)
        .background(isUser ? LuxuryTheme.surfaceCard : AppColors.depth)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(14)
        .foregroundColor(AppColors.textPrimary)
    }
}

private struct LegalOSDocumentPanel: View {
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel
    @State private var isCollapsed: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Evidence")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer(minLength: 0)

                    if isCollapsed {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                DocumentListView()
                    .luxuryCard()
                    .frame(maxHeight: .infinity)
                    .padding(.top, 2)
            } else {
                Spacer(minLength: 0)
                    .frame(height: 2)
            }
        }
    }
}
