import SwiftUI

struct MainDashboardView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var caseTreeViewModel = CaseTreeViewModel()
    @StateObject private var learningViewModel = LearningViewModel()
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel

    @State private var showHamburgerMenu = false
    @State private var showLearning = false
    @State private var showLegalDisclaimer = false
    @State private var showPrivacyPolicy = false
    @StateObject private var voiceRecorder = VoiceRecorder()

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: [search] [Ask AI Lawyer] [hamburger]
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.white)
                Text("Ask AI Lawyer")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(Color("GoldAccent"))
                    .frame(maxWidth: .infinity)
                Button(action: { showHamburgerMenu = true }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color("BackgroundNavy"))

            // Body: left sidebar (~25%) | chat (rest)
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    CaseManagementPanel(showLearning: $showLearning)
                        .environmentObject(caseTreeViewModel)
                        .environmentObject(learningViewModel)
                        .frame(width: geo.size.width * 0.25)

                    Divider()
                        .frame(width: 1)
                        .background(Color.white.opacity(0.2))

                    VStack(spacing: 0) {
                        switch caseTreeViewModel.selectedSubfolder {
                        case .timeline:
                            TimelineView()
                                .environmentObject(caseTreeViewModel)
                        case .documents, .filedDocuments, .recordings, .history:
                            DocumentListView()
                                .environmentObject(caseTreeViewModel)
                        default:
                            // Evidence, Response: show chat (main content) and generated docs
                            ChatTranscriptView()
                                .environmentObject(chatViewModel)
                                .environmentObject(caseTreeViewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color("BackgroundNavy").opacity(0.98))

            // Bottom: Type input + mic
            HStack(spacing: 10) {
                Button {
                    Task {
                        if voiceRecorder.isRecording {
                            let text = await voiceRecorder.stopRecordingAndTranscribe()
                            if !text.isEmpty { chatViewModel.sendText(text) }
                        } else {
                            _ = await voiceRecorder.startRecording()
                        }
                    }
                } label: {
                    Image(systemName: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundColor(voiceRecorder.isRecording ? .red : Color("GoldAccent"))
                }
                .disabled(chatViewModel.isSending)

                TextField("Type", text: $chatViewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(24)
                    .lineLimit(1...4)

                Button(action: { chatViewModel.sendCurrentMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color("GoldAccent"))
                }
                .disabled(chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatViewModel.isSending)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color("BackgroundNavy"))
            .alert("Voice input", isPresented: Binding(
                get: { voiceRecorder.errorMessage != nil },
                set: { if !$0 { voiceRecorder.errorMessage = nil } }
            )) {
                Button("OK") { voiceRecorder.errorMessage = nil }
            } message: {
                Text(voiceRecorder.errorMessage ?? "")
            }
        }
        .background(Color("BackgroundNavy").ignoresSafeArea())
        .sheet(isPresented: $showHamburgerMenu) {
            HamburgerMenuView(
                showLegalDisclaimer: $showLegalDisclaimer,
                showPrivacyPolicy: $showPrivacyPolicy
            )
        }
        .sheet(isPresented: $showLearning) {
            NavigationView {
                LearningView().environmentObject(learningViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLearning = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLegalDisclaimer) {
            NavigationView {
                LegalDisclaimerView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLegalDisclaimer = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationView {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPrivacyPolicy = false }
                        }
                    }
            }
        }
    }
}

struct ChatTranscriptView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel

    var body: some View {
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chatViewModel.messages) { message in
                        HStack(alignment: .top) {
                            if message.sender == .user {
                                bubble(for: message)
                                Spacer(minLength: 40)
                            } else {
                                Spacer(minLength: 40)
                                VStack(alignment: .trailing, spacing: 8) {
                                    bubble(for: message)
                                    if message.isDocumentOffer {
                                        documentOfferButton(for: message)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        Text(message.text)
            .padding(12)
            .background(message.sender == .user ? Color(white: 0.22) : Color("GoldAccent").opacity(0.25))
            .foregroundColor(.white)
            .cornerRadius(14)
            .frame(maxWidth: 280, alignment: message.sender == .user ? .leading : .trailing)
    }

    @ViewBuilder
    private func documentOfferButton(for message: ChatMessage) -> some View {
        Button {
            guard let caseFolder = caseTreeViewModel.selectedCase else { return }
            let name = "Draft \(Date().formatted(date: .abbreviated, time: .omitted))"
            let content = "This is a placeholder for the generated document. When the real API is connected, the AI will fill this with the actual draft.\n\nGenerated by Ask AI Lawyer."
            if caseTreeViewModel.addGeneratedDocument(caseId: caseFolder.id, subfolder: .documents, name: name, content: content) != nil {
                let confirm = ChatMessage(sender: .ai, text: "I've added \"\(name)\" to your Documents folder and timeline. Open the Documents folder in the sidebar to view it, or open Timeline to see the event. You can download or share it from there.")
                chatViewModel.messages.append(confirm)
            }
        } label: {
            Text("Yes, generate document")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Color("BackgroundNavy"))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color("GoldAccent"))
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}
