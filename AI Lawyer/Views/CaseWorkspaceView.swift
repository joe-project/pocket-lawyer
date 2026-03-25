import SwiftUI

/// Unified case workspace: one scroll with card-based sections (Case Brief, Progress, Suggested Actions, Timeline, Evidence, Chat). Used for simplicity and clarity.
struct CaseWorkspaceView: View {
    @EnvironmentObject var workspace: WorkspaceManager
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var caseManager: CaseManager

    @State private var nextAction: NextAction?
    @State private var nextActionLoading = false
    @State private var nextActionError: String?
    @State private var upgradePromptToShow: UpgradePrompt?
    @State private var showInviteSheet = false
    @State private var currentInvitation: CaseInvitation?
    @State private var showTypeStorySheet = false
    @State private var showRecordStorySheet = false
    @State private var storyDraft = ""
    @State private var storyError: String?
    @StateObject private var voiceRecorder = VoiceRecorder()

    private var caseTreeViewModel: CaseTreeViewModel { workspace.caseTreeViewModel }
    private static let nextActionEngine = NextActionEngine()

    var body: some View {
        Group {
            if let state = workspace.currentCaseState, let analysis = state.analysis {
                VStack(spacing: 0) {
                    caseCommandBar(onNextAction: fetchNextAction)
                    if isAnalyzing(caseId: state.caseId) {
                        analyzingBanner
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: LuxuryTheme.workspaceCardSpacing) {
                            if let action = nextAction {
                                nextActionCard(action)
                            }

                            Group {
                                if let brief = CaseBriefStore.shared.brief(for: state.caseId) {
                                    CaseBriefCardView(brief: brief)
                                } else {
                                    CaseBriefView(analysis: analysis)
                                }
                            }
                            .id("brief")

                            CaseProgressView(progress: CaseProgressStore.shared.progress(for: state.caseId))
                                .id("progress")

                            SuggestedActionsCardView(
                                analysis: analysis,
                                onSuggestedAction: { section in
                                    if let sub = section.documentSubfolder {
                                        caseTreeViewModel.selectedSubfolder = sub
                                    }
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(sectionAnchor(for: section), anchor: .top)
                                    }
                                }
                            )
                            .id("actions")

                            EvidenceAlertsView(alerts: state.evidenceAlerts)

                            LegalArgumentsView(arguments: state.legalArguments)

                            timelineCard(caseId: state.caseId)
                                .id("timeline")

                            evidenceCard(caseId: state.caseId)
                                .id("evidence")

                            chatCard()
                                .id("chat")
                        }
                        .padding(LuxuryTheme.workspaceCardSpacing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .sheet(isPresented: $showInviteSheet) {
                    inviteParticipantSheet
                }
            } else {
                emptyStateView
            }
        }
        .background(AppColors.background)
        .sheet(item: $upgradePromptToShow) { prompt in
            UpgradePromptSheet(prompt: prompt) { upgradePromptToShow = nil }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Text("Start Your Case")
                .font(LuxuryTheme.sectionFont(size: 22))
                .foregroundColor(AppColors.textPrimary)

            Text("Tell us what happened and we’ll begin building your legal case.")
                .font(LuxuryTheme.bodyFont(size: 15))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button {
                    beginCaseIntake(mode: .record)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(AppTypography.body)
                        Text("Record Your Story")
                            .font(LuxuryTheme.buttonFont(size: 16))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(AppButtonStyle())

                Button {
                    beginCaseIntake(mode: .type)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(AppTypography.body)
                        Text("Type Your Story")
                            .font(LuxuryTheme.buttonFont(size: 16))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(AppButtonStyle())
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)

            if let storyError {
                Text(storyError)
                    .font(LuxuryTheme.bodyFont(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let caseId = workspace.selectedCaseId ?? caseTreeViewModel.selectedCase?.id,
               isAnalyzing(caseId: caseId) {
                analyzingBanner
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
            }
        }
        .padding(20)
        .luxuryCard()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .sheet(isPresented: $showTypeStorySheet) {
            typeStorySheet
        }
        .sheet(isPresented: $showRecordStorySheet) {
            recordStorySheet
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

    private func isAnalyzing(caseId: UUID) -> Bool {
        chatViewModel.isSending || conversationManager.analyzingCaseIds.contains(caseId)
    }

    private var analyzingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(AppColors.primary)
            Text("Analyzing your case...")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LuxuryTheme.workspaceCardSpacing)
        .padding(.vertical, 10)
        .background(AppColors.background)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(LuxuryTheme.navBarBorder),
            alignment: .bottom
        )
    }

    private enum IntakeMode {
        case record
        case type
    }

    private func beginCaseIntake(mode: IntakeMode) {
        storyError = nil
        storyDraft = ""
        guard let caseId = workspace.selectedCaseId ?? caseTreeViewModel.selectedCase?.id else {
            storyError = "Select a case to start."
            return
        }

        // Immediately create initial CaseMemory (even before any story is provided).
        CaseMemoryStore.shared.setMemory(CaseMemory(), forCaseId: caseId)

        switch mode {
        case .type:
            showTypeStorySheet = true
        case .record:
            showRecordStorySheet = true
            Task { _ = await voiceRecorder.startRecording() }
        }

        // Trigger reasoning immediately (initially from empty memory). When story is submitted,
        // we update memory and enqueue reasoning again.
        Task { @MainActor in
            conversationManager.enqueueReasoning(caseId: caseId)
        }
    }

    private var typeStorySheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type your story")
                    .font(LuxuryTheme.sectionFont(size: 18))
                    .foregroundColor(AppColors.textPrimary)

                TextEditor(text: $storyDraft)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(10)
                    .background(LuxuryTheme.surfaceCard)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                    )
                    .frame(minHeight: 180)

                Spacer()
            }
            .padding(20)
            .background(AppColors.background)
            .navigationTitle("Start Your Case")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTypeStorySheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        submitStoryAndRefresh()
                        showTypeStorySheet = false
                    }
                    .disabled(storyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var recordStorySheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Record your story")
                    .font(LuxuryTheme.sectionFont(size: 18))
                    .foregroundColor(AppColors.textPrimary)

                Text("Tap stop when you're done. We'll transcribe and use it to build your case memory.")
                    .font(LuxuryTheme.bodyFont(size: 13))
                    .foregroundColor(AppColors.textPrimary)

                Button {
                    Task {
                        if voiceRecorder.isRecording {
                            let text = await voiceRecorder.stopRecordingAndTranscribe()
                            await MainActor.run { storyDraft = text }
                        } else {
                            _ = await voiceRecorder.startRecording()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                            .foregroundColor(voiceRecorder.isRecording ? .red : AppColors.textPrimary)
                        Text(voiceRecorder.isRecording ? "Stop & Transcribe" : "Start Recording")
                            .font(LuxuryTheme.buttonFont(size: 16))
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(AppButtonStyle())

                if !storyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Transcript")
                        .font(LuxuryTheme.sectionFont(size: 14))
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.top, 8)

                    ScrollView {
                        Text(storyDraft)
                            .font(LuxuryTheme.bodyFont(size: 14))
                            .foregroundColor(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(LuxuryTheme.surfaceCard)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                            )
                    }
                    .frame(maxHeight: 220)
                }

                Spacer()
            }
            .padding(20)
            .background(AppColors.background)
            .navigationTitle("Start Your Case")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if voiceRecorder.isRecording {
                            Task { _ = await voiceRecorder.stopRecordingAndTranscribe() }
                        }
                        showRecordStorySheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        submitStoryAndRefresh()
                        showRecordStorySheet = false
                    }
                    .disabled(storyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func submitStoryAndRefresh() {
        let info = storyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !info.isEmpty else { return }
        guard let caseId = workspace.selectedCaseId ?? caseTreeViewModel.selectedCase?.id else { return }

        Task {
            do {
                _ = try await CaseMemoryStore.shared.updateMemory(caseId: caseId, newInformation: info)
            } catch {
                await MainActor.run { storyError = error.localizedDescription }
            }
            Task { @MainActor in
                conversationManager.enqueueReasoning(caseId: caseId)
            }
        }
    }

    private func sectionAnchor(for section: CaseWorkspaceSection) -> String {
        switch section {
        case .evidence, .documents, .history: return "evidence"
        case .timeline: return "timeline"
        case .chat: return "chat"
        default: return "actions"
        }
    }

    // MARK: - Timeline card

    private func timelineCard(caseId: UUID) -> some View {
        let events = caseTreeViewModel.events(for: caseId)
        return VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "📅", title: "Timeline")
            if events.isEmpty {
                Text("No timeline events yet. Tasks, filings, and evidence will appear here.")
                    .pocketSecondaryMonospaced(size: 14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events.prefix(10)) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: iconForTimelineKind(event.kind))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 24, alignment: .center)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .pocketSecondaryMonospaced(size: 14)
                                if let summary = event.summary, !summary.isEmpty {
                                    Text(summary)
                                        .pocketSecondaryMonospaced(size: 12)
                                }
                                Text(event.createdAt, style: .date)
                                    .pocketSecondaryMonospaced(size: 11)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        if event.id != events.prefix(10).last?.id {
                            Divider()
                                .background(LuxuryTheme.cardBorder)
                        }
                    }
                    if events.count > 10 {
                        Text("+ \(events.count - 10) more")
                            .pocketSecondaryMonospaced(size: 12)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
        .onChange(of: chatViewModel.messages.count) { _, count in
            print("UI RECEIVED MESSAGES:", count)
        }
    }

    private func iconForTimelineKind(_ kind: TimelineEventKind) -> String {
        switch kind {
        case .task: return "checkmark.circle.fill"
        case .filing: return "doc.fill"
        case .response: return "arrowshape.turn.up.left.fill"
        }
    }

    // MARK: - Evidence card

    private func evidenceCard(caseId: UUID) -> some View {
        let files = caseTreeViewModel.files(for: caseId, subfolder: .evidence)
        return VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "📁", title: "Evidence")
            if files.isEmpty {
                Text("No evidence yet. Add photos, documents, or other files to support your case.")
                    .pocketSecondaryMonospaced(size: 14)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(files.prefix(8)) { file in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(AppTypography.body)
                                .foregroundColor(.gray)
                            Text(file.name)
                                .pocketSecondaryMonospaced(size: 14)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    if files.count > 8 {
                        Text("+ \(files.count - 8) more")
                            .pocketSecondaryMonospaced(size: 12)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    // MARK: - Chat card

    private func chatCard() -> some View {
        let caseId = workspace.selectedCaseId ?? caseTreeViewModel.selectedCase?.id
        let messages = chatViewModel.messages
            .filter { msg in
                guard let caseId = caseId else { return msg.caseId == nil }
                return msg.caseId == caseId
            }
            .map { msg in
            ChatMessage(
                id: msg.id,
                sender: msg.role == "user" ? .user : .ai,
                text: msg.content + (msg.attachmentNames.isEmpty ? "" : "\n(Attachments: \(msg.attachmentNames.joined(separator: ", ")))"),
                date: msg.timestamp
            )
        }
        return VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "💬", title: "Chat")
            if messages.isEmpty {
                Text("No messages yet. Use the input bar below to describe your case or ask questions.")
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages.suffix(20)) { message in
                        HStack(alignment: .top) {
                            if message.sender == .user {
                                chatBubble(message, isUser: true)
                                Spacer(minLength: 40)
                            } else {
                                Spacer(minLength: 40)
                                chatBubble(message, isUser: false)
                            }
                        }
                    }
                }
            }
            if conversationManager.offeringResumeIntake {
                Button {
                    chatViewModel.resumeIntake()
                } label: {
                    Text("Resume intake")
                        .font(LuxuryTheme.buttonFont(size: 14))
                }
                .buttonStyle(AppButtonStyle())
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private func chatBubble(_ message: ChatMessage, isUser: Bool) -> some View {
        Text(message.text)
            .font(LuxuryTheme.bodyFont(size: 15))
            .padding(12)
            .background(isUser ? LuxuryTheme.surfaceCard : Color(red: 1, green: 122/255, blue: 89/255, opacity: 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
            )
            .cornerRadius(14)
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: 280, alignment: isUser ? .leading : .trailing)
    }

    // MARK: - Next action card

    private func nextActionCard(_ action: NextAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggested next step")
                    .font(LuxuryTheme.sectionFont(size: 12))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if nextActionLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppColors.primary)
                }
            }
            Text(action.title)
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text(action.description)
                .font(LuxuryTheme.bodyFont(size: 15))
                .foregroundColor(AppColors.textPrimary)
            if let error = nextActionError {
                Text(error)
                    .font(LuxuryTheme.bodyFont(size: 12))
                    .foregroundColor(.red)
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private func caseCommandBar(onNextAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {
                onNextAction()
            } label: {
                HStack(spacing: 8) {
                    if nextActionLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.textPrimary))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "lightbulb.fill")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.primary)
                    }
                    Text("What Should I Do Next?")
                        .font(LuxuryTheme.bodyFont(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(LuxuryTheme.surfaceCard)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(nextActionLoading)

            if let caseId = workspace.selectedCaseId {
                Button {
                    let inv = workspace.caseCollaborationEngine.createInvitation(caseId: caseId)
                    currentInvitation = inv
                    showInviteSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.primary)
                        Text("Invite Participant")
                            .font(LuxuryTheme.bodyFont(size: 15))
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(LuxuryTheme.surfaceCard)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, LuxuryTheme.workspaceCardSpacing)
        .padding(.vertical, 12)
        .background(AppColors.background)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(LuxuryTheme.navBarBorder),
            alignment: .bottom
        )
    }

    private var inviteParticipantSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Share this link with the person you want to invite. They will have access only to this case and can upload evidence or record statements.")
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let inv = currentInvitation {
                    let link = workspace.caseCollaborationEngine.invitationURL(for: inv.token)
                    Text(link)
                        .font(LuxuryTheme.bodyFont(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LuxuryTheme.surfaceCard)
                        .cornerRadius(10)
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = link
                        } label: {
                            Label("Copy link", systemImage: "doc.on.doc")
                                .font(LuxuryTheme.buttonFont(size: 15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppButtonStyle())
                        Button {
                            let av = UIActivityViewController(activityItems: [link], applicationActivities: nil)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let root = windowScene.windows.first?.rootViewController {
                                root.present(av, animated: true)
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(LuxuryTheme.buttonFont(size: 15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppButtonStyle())
                    }
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppColors.background)
            .navigationTitle("Invite Participant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showInviteSheet = false
                        currentInvitation = nil
                    }
                }
            }
        }
    }

    private func fetchNextAction() {
        guard let state = workspace.currentCaseState, let analysis = state.analysis else { return }
        nextActionError = nil
        nextActionLoading = true
        let evidenceSummaries: [EvidenceAnalysis] = state.evidence.map { file in
            let summary = (file.content?.trimmingCharacters(in: .whitespacesAndNewlines))
                .map { $0.count > 500 ? String($0.prefix(500)) + "…" : $0 }
                ?? file.name
            return EvidenceAnalysis(
                summary: summary,
                violations: [],
                damages: nil,
                timelineEvents: [],
                deadlines: [],
                missingEvidence: nil
            )
        }
        let timeline = analysis.timeline
        let engine = Self.nextActionEngine
        Task.detached(priority: .userInitiated) {
            do {
                let action = try await engine.recommendNextAction(
                    caseAnalysis: analysis,
                    evidence: evidenceSummaries,
                    timeline: timeline
                )
                await MainActor.run {
                    nextAction = action
                    nextActionLoading = false
                }
            } catch {
                await MainActor.run {
                    nextActionError = error.localizedDescription
                    nextActionLoading = false
                }
            }
        }
    }
}
