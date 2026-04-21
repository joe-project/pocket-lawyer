# Pocket Lawyer Project Handoff

## Purpose
Pocket Lawyer is a SwiftUI iOS app for building and organizing legal matters around a case-aware AI workflow.

The app is not just a chat client. It combines:
- AI chat
- case management
- evidence and document storage
- timeline tracking
- document generation/autofill
- strategy/reasoning pipelines
- local on-device folder/file persistence

This document describes the current architecture and the main logic flow as it exists now.

## Top-Level App Structure

### App Entry
- File: [AILawyerApp.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/AILawyerApp.swift)
- The app creates one shared `WorkspaceManager` and injects it into SwiftUI via `.environmentObject(...)`.
- The following shared instances are injected from that workspace:
  - `WorkspaceManager`
  - `ChatViewModel`
  - `ConversationManager`
  - `CaseManager`
  - `SubscriptionViewModel`

This matters because the app relies on one shared state graph. Chat, case selection, and file routing all depend on the same instances.

## Primary Shared Coordinator

### WorkspaceManager
- File: [WorkspaceManager.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/WorkspaceManager.swift)

`WorkspaceManager` is the root composition object for the app.

It creates and owns:
- `CaseManager`
- `ConversationManager`
- `ChatViewModel`
- `CaseTreeViewModel`
- `CaseReasoningEngine`
- `LitigationStrategyEngine`
- `CaseConfidenceEngine`
- `DocumentEngine`
- `EmailDraftEngine`
- `LegalDeadlineTracker`
- `EvidenceAnalysisEngine`
- `LegalResearchService`
- `CaseCollaborationEngine`

It also owns:
- selected case state
- invited participant mode
- per-case strategy cache
- per-case confidence cache

Main responsibilities:
- initialize all engines with shared dependencies
- keep selected case in sync with the sidebar tree
- coordinate case analysis refresh and strategy updates
- process uploaded evidence into case reasoning
- expose a full `CaseState` snapshot for a given case

This is the safest place to think of as the app’s composition root.

## UI Layout and Navigation

### RootContainerView
- File: [RootContainerView.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Views/RootContainerView.swift)

`RootContainerView` is the main shell.

It handles:
- onboarding / welcome flow
- legal disclaimer acceptance
- top bar
- slide-out sidebar
- main workspace body
- bottom `ChatInputBar`

Important behavior:
- the top bar is fixed
- the sidebar slides independently
- the chat input is inserted with `safeAreaInset(edge: .bottom)`
- the sidebar gesture behavior is custom and intentionally restricted to specific hit areas

### MainContentView
- File: [MainDashboardView.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Views/MainDashboardView.swift)

This is the main workspace container inside the shell.

Current setup:
- it renders `CaseWorkspaceView()` as the primary content area
- it wires `ChatViewModel`, `ConversationManager`, and `CaseTreeViewModel` together on appear
- it syncs selected case / selected subfolder / selected file into the chat layer
- it also handles contextual monetization notifications and the hamburger menu sheets

### Sidebar
- File: [MainDashboardView.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Views/MainDashboardView.swift)
- The sidebar is implemented in the same file under `SidebarView`

The sidebar manages:
- case list display
- section ordering
- case creation
- rename/delete flows
- subfolder visibility
- tree expansion
- workspace section selection

## Case Storage Model

### CaseTreeViewModel
- File: [CaseTreeViewModel.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/ViewModels/CaseTreeViewModel.swift)

This is the live case/file tree model used by the sidebar and workspace.

It owns:
- `cases: [CaseFolder]`
- `selectedCase`
- `selectedWorkspaceSection`
- `selectedSubfolder`
- `selectedFileId`
- `timelineEvents`

Persistence:
- uses `LocalCaseStorage.shared`
- stores case folders and timeline data locally on device

Main responsibilities:
- seed/migrate starter folders
- create, rename, delete cases
- show/hide subfolders
- add and update files
- upsert text-based artifacts
- add timeline events
- manage selected workspace section and file focus

Important design point:
- the case tree is the source of truth for local case files and timeline artifacts
- chat replies, evidence updates, and generated documents are routed back into this structure

## Chat Architecture

### ChatViewModel
- File: [ChatViewModel.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/ViewModels/ChatViewModel.swift)

`ChatViewModel` is the UI-facing chat layer.

It owns:
- `messages`
- `inputText`
- `isSending`
- `errorMessage`
- `isIntakeActive`
- `latestCaseAnalysis`
- pending attachments
- selected case/file/subfolder bindings for the active workspace context

Important behavior:
- it does not own the real message store
- it binds to `conversationManager.$messages`
- `ConversationManager.messages` is the effective message source of truth

Send flow:
1. user types or attaches files
2. `sendCurrentMessage()` calls `sendText(...)`
3. `sendText(...)` checks current case selection and intent handlers
4. if the message is a normal chat turn, it delegates to `ConversationManager.submitUserContent(...)`

It also handles:
- folder suggestion replies
- pending case update replies
- direct case commands
- voice transcript submission

### ConversationManager
- File: [ConversationManager.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/ConversationManager.swift)

This is the core orchestration layer for case-aware chat.

It owns:
- shared `messages`
- guided conversation stage tracking
- pending update suggestions
- folder suggestion state
- analyzing case ids
- auto-trigger state like last strategy offer counts

Main responsibilities:
- append user and assistant messages
- route special replies like yes/no strategy consent
- build autonomous case context for AI requests
- run AI chat requests
- parse structured system data from AI responses
- sync evidence/timeline/doc/strategy artifacts into the case tree
- offer strategy and folder suggestions
- enqueue background case reasoning

### Current Chat Flow

#### Standard user message flow
1. `ChatInputBar` sends through `ChatViewModel`
2. `ChatViewModel.sendText(...)`
3. `ConversationManager.submitUserContent(...)`
4. a user `Message` is created and appended
5. legal signal extraction runs on the user content
6. structured case payload may be synced immediately into the case tree
7. case memory is updated asynchronously
8. `ConversationManager.getAIReply(...)` is called
9. guided AI request is built based on conversation stage
10. `AIEngine.chat(...)` is called with:
   - latest user text
   - previous case messages
   - case context block
   - optional structured output requirement
11. response is parsed
12. visible assistant text is appended
13. structured data may update:
   - timeline
   - evidence registry
   - document checklist
   - strategy notes
14. the reply is also saved into the active case folder as a versioned artifact

#### Failure handling
The current chat path has multiple fallbacks:
- structured autonomous request
- plain backend retry
- plain retry without prior context
- local emergency reply generation inside `ConversationManager`

That means the chat should not return `nil` from the normal send flow anymore unless something outside this path breaks.

## AI Layer

### AIEngine
- File: [AIEngine.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/AIEngine.swift)

`AIEngine` is the central AI orchestration layer. Other features depend on it instead of calling the network directly.

Main public capabilities:
- `chat(...)`
- `analyzeCase(...)`
- `analyzeEvidenceDocument(...)`
- `recommendNextAction(...)`
- `updateLitigationStrategy(...)`
- `evaluateConfidence(...)`
- `generateDocument(...)`

Important current behavior in `chat(...)`:
- accepts previous conversation messages
- accepts an optional `caseContext`
- can append a structured output requirement

When structured output is requested, the model is asked for:
- `VISIBLE RESPONSE`
- `SYSTEM DATA (JSON)`

The JSON is used by `ConversationManager` to update the case in the background.

### OpenAIService
- File: [OpenAIService.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/OpenAIService.swift)

This is the network layer.

Important points:
- the app does not use a client-side API key
- requests go through a Cloudflare Worker endpoint
- request timeout is set explicitly
- request body / raw response / errors are logged
- the service returns:
  - assistant text
  - whether the response offers a document
  - parsed timeline events

Current endpoint:
- `https://ai-lawyer-server.ailawyer.workers.dev`

## Memory, Reasoning, and Analysis

### CaseMemoryStore / CaseMemoryEngine
- Files:
  - [CaseMemoryStore.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/CaseMemoryStore.swift)
  - [CaseMemoryEngine.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/CaseMemoryEngine.swift)

This subsystem stores lightweight structured memory per case:
- people
- events
- evidence
- claims
- damages estimate

Memory is stored on device and updated over time so the AI does not need to infer everything from scratch every turn.

### CaseReasoningEngine
- File: [CaseReasoningEngine.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/CaseReasoningEngine.swift)

This engine updates the case-level reasoning output.

It works from a `CaseContext` built from:
- messages
- timeline
- evidence
- recordings
- cached case analysis
- litigation strategy
- case memory
- optional legal research appendix

### CaseManager
- File: [CaseManager.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/CaseManager.swift)

`CaseManager` is the structured case-analysis store.

It holds:
- case records
- parsed `CaseAnalysis`
- updates to analysis per case

This is distinct from `CaseTreeViewModel`:
- `CaseTreeViewModel` = local folder/file/timeline UI model
- `CaseManager` = structured legal analysis model

### CaseContextCache and Result Cache
- Files:
  - [CaseContextCache.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/CaseContextCache.swift)
  - [CaseAnalysisResultCache.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/CaseAnalysisResultCache.swift)

These reduce repeated work by caching:
- analysis
- strategy
- evidence summaries
- timeline events
- recording transcripts

## Structured Legal Workflow Layer

### LegalSignalExtractor
- File: [LegalSignalExtractor.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/LegalSignalExtractor.swift)

This extracts structured clues from user messages, such as:
- facts
- evidence clues
- document needs
- deadlines
- requested actions

### ConversationPlanner
- File: [ConversationPlanner.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/ConversationPlanner.swift)

This helps decide what the chat should do next, including:
- follow-up questions
- whether to stay conversational
- whether to offer strategy
- whether to offer documents or timeline help

### CaseWorkflowModels
- File: [CaseWorkflowModels.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Models/CaseWorkflowModels.swift)

This file contains typed workflow models like:
- `WorkflowEvidenceItem`
- `DocumentRequirement`
- `FilingInstruction`
- `StrategyNote`
- `FollowUpQuestion`
- `ExtractedLegalFact`
- `CaseUpdatePayload`

These are the typed bridge between chat and structured legal work product.

## Documents and Evidence

### DocumentProcessingService
- File: [DocumentProcessingService.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/DocumentProcessingService.swift)

Purpose:
- classify uploaded documents
- parse fillable PDFs
- extract text from PDFs
- OCR scanned PDFs/images

### DocumentAutofillService
- File: [DocumentAutofillService.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/DocumentAutofillService.swift)

Purpose:
- map existing case/chat/context into candidate form answers
- keep confidence metadata
- avoid silently inventing missing facts

### CompletedDocumentWriter
- File: [CompletedDocumentWriter.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Services/CompletedDocumentWriter.swift)

Purpose:
- write filled values to fillable PDFs
- create completed overlay versions for flat/scanned forms
- generate predictable completed filenames

### DocumentListView
- File: [DocumentListView.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Views/DocumentListView.swift)

This is the main UI integration point for document intake/export within the current app structure.

## Sidebar / Folder Logic

The current sidebar model is folder-tree based.

Cases and research items are stored as `CaseFolder` records with:
- category
- visible/hidden subfolders
- custom folder display names
- files by subfolder

The sidebar supports:
- add folder
- rename folder
- delete folder
- reveal/hide subfolders
- rename subfolders

The selected folder and selected workspace section drive what appears on the right side.

## Case Workspace Logic

### CaseWorkspaceView
- File: [CaseWorkspaceView.swift](/Users/user/Desktop/AI%20Lawyer/AI%20Lawyer/Views/CaseWorkspaceView.swift)

This is the main right-side workspace.

It is currently responsible for showing:
- chat
- timeline
- evidence
- documents
- related case content

Important recent behavior:
- the chat section is the main conversational surface
- opening a folder defaults into chat-oriented case work rather than a generic overview dump

## Persistence Model

Current persistence is primarily local.

Main local storage pieces:
- `LocalCaseStorage`
- `CaseMemoryStore`
- case files within `CaseTreeViewModel`
- timeline events in `CaseTreeViewModel`

Important product behavior:
- case content and generated artifacts are intended to remain local/on-device
- original and generated files are stored separately when appropriate

## Main Logic Boundaries

### What owns UI state
- `ChatViewModel`
- `CaseTreeViewModel`
- SwiftUI state in `RootContainerView` / `MainContentView`

### What owns case structure
- `CaseTreeViewModel`
- `LocalCaseStorage`

### What owns structured legal analysis
- `CaseManager`
- `CaseReasoningEngine`
- `AIEngine`

### What owns live chat orchestration
- `ConversationManager`

### What owns networking
- `OpenAIService`

## Important Current Design Rules

The current project assumes:
- one shared `WorkspaceManager`
- one shared `ConversationManager`
- one shared `ChatViewModel`
- one shared `CaseTreeViewModel`

Breaking this by instantiating new local chat or workspace objects inside views will cause desync bugs.

Also important:
- messages should be routed through `ConversationManager.submitUserContent(...)`
- assistant replies should be saved through `appendAssistantResponse(...)`
- case artifacts should flow back through `CaseTreeViewModel` helpers instead of ad hoc local storage

## Known Architectural Patterns

The project generally follows these patterns:
- SwiftUI + observable objects
- additive feature services rather than one monolith
- one shared workspace graph
- case-aware routing
- local persistence with background AI enrichment
- AI output -> parser -> structured case update

## Suggested Mental Model For Future Work

If you are changing the app, think in this order:

1. Is this UI-only, or does it change case structure?
2. If it affects a case artifact, should it live in `CaseTreeViewModel`?
3. If it affects structured legal reasoning, should it live in `CaseManager` / `CaseReasoningEngine`?
4. If it affects live chat behavior, should it go through `ConversationManager`?
5. If it affects model calls or prompts, should it go through `AIEngine`?
6. If it touches the backend request shape or response parsing, it belongs in `OpenAIService`

## Current High-Risk Areas

These are the most sensitive parts of the app:
- `ConversationManager`
- `ChatViewModel`
- `CaseTreeViewModel`
- `WorkspaceManager`
- `AIEngine`
- `OpenAIService`

Reason:
- they sit on the critical path for chat, case storage, and UI synchronization

## Recommended Next Documentation Files

If you want deeper internal docs later, the next useful docs would be:
- `CHAT_PIPELINE.md`
- `CASE_STORAGE_MODEL.md`
- `DOCUMENT_AUTOFILL_FLOW.md`
- `AI_PROMPTS_AND_STRUCTURED_OUTPUTS.md`

## Handoff Summary

Today’s system is best understood as:

- a shared workspace container
- a local case/file tree
- a structured case-analysis store
- a chat orchestrator that writes into both
- an AI layer that can produce both conversational output and structured case updates

That is the current working mental model for Pocket Lawyer.
