# Pocket Lawyer Logic Handoff

This handoff explains how Pocket Lawyer turns chat into case work product: how user messages move through the app, how AI prompts and typed models are used, and how structured legal artifacts are saved back into the case workspace.

## Big Picture

Pocket Lawyer is not only a chat UI. The visible chat is intentionally short, but behind the scenes the app builds and updates a structured legal case file.

The core loop is:

1. User sends a message or uploads evidence.
2. The app extracts local legal signals immediately.
3. The app builds case context from memory, analysis, evidence, timeline, strategy, and recent chat.
4. `AIEngine` asks the model for a short visible reply plus structured JSON.
5. `ConversationManager` parses the response.
6. The visible reply goes into chat.
7. Structured data is mapped into typed Swift models.
8. Case artifacts are saved through `CaseTreeViewModel`, not an ad hoc store.

## Main Files

- `AI Lawyer/Views/RootContainerView.swift`
  - Main shell: fixed top bar, sliding sidebar, main workspace, bottom `ChatInputBar`.

- `AI Lawyer/Views/MainDashboardView.swift`
  - Main workspace wiring.
  - Connects `ChatViewModel`, `ConversationManager`, `CaseTreeViewModel`, and `CaseManager`.
  - Contains sidebar and workspace section selection logic.

- `AI Lawyer/ViewModels/ChatViewModel.swift`
  - UI-facing chat state.
  - Handles typed input, attachments, and sends user messages into `ConversationManager`.

- `AI Lawyer/Services/ConversationManager.swift`
  - Main chat and case orchestration layer.
  - Owns message flow, AI reply flow, structured response parsing, artifact sync, offers, and case update routing.

- `AI Lawyer/Services/AIEngine.swift`
  - Central wrapper for model calls.
  - Builds the prompt contract for visible chat plus structured system data.

- `AI Lawyer/Services/LegalSignalExtractor.swift`
  - Local heuristic fallback.
  - Extracts case type, evidence, documents, timeline hints, strategy notes, coaching, decision pathways, say/don't-say guidance, and response analysis signals before or without the model.

- `AI Lawyer/Models/CaseWorkflowModels.swift`
  - Typed structured payload models.
  - Defines `CaseUpdatePayload` and artifact-specific types like `DecisionTreePathway`, `SayDontSayGuidance`, `CoachingPoint`, and `ResponseAnalysis`.

- `AI Lawyer/ViewModels/CaseTreeViewModel.swift`
  - Canonical case artifact routing and local file tree state.
  - Saves structured artifacts into existing case folders/subfolders.

- `AI Lawyer/Services/LocalCaseStorage.swift`
  - Local persistence for case files, folders, and metadata.

## Runtime Ownership

`WorkspaceManager` is the composition root. It creates and wires the shared app objects:

- `CaseManager`
- `ConversationManager`
- `ChatViewModel`
- `CaseTreeViewModel`
- `CaseReasoningEngine`
- `LitigationStrategyEngine`
- `CaseConfidenceEngine`
- `DocumentEngine`
- evidence, research, deadline, and collaboration services

The app depends on shared instances. Do not create new isolated stores for chat, case artifacts, or generated deliverables unless the architecture is intentionally changed.

## Chat Flow

Standard message flow:

```text
ChatInputBar
  -> ChatViewModel.sendCurrentMessage()
  -> ChatViewModel.sendText(...)
  -> ConversationManager.submitUserContent(...)
  -> LegalSignalExtractor.extract(...)
  -> ConversationManager.getAIReply(...)
  -> AIEngine.chat(...)
  -> ConversationManager.parseChatEnvelope(...)
  -> visible assistant message
  -> sync structured payload into CaseTreeViewModel
```

Important behavior:

- `ChatViewModel` is UI-facing, but `ConversationManager.messages` is the effective source of truth for stored chat messages.
- User messages are associated with the selected case when a case is active.
- Attachments are passed into the send flow and can become evidence signals.
- The assistant should stay short and conversational.
- Structured case work product should be saved into case artifacts, not dumped into visible chat.

## Local Signal Extraction

Before the model response matters, `LegalSignalExtractor` creates a `CaseUpdatePayload` from the user's text and attachments.

It detects:

- case type, such as landlord-tenant, employment, injury, protection order, criminal-adjacent
- jurisdiction hints
- evidence items
- document requirements
- filing instructions
- strategy notes
- coaching points
- decision tree pathways
- say/don't-say guidance
- response analysis
- timeline events
- follow-up questions
- the best single next deliverable to offer

This is a safety net. Even if the model fails or the structured JSON is missing, the app can still capture useful case signals.

## AI Prompt Contract

`AIEngine.guidedCaseChatSystemPrompt` defines the assistant's tone and behavior.

Key rules:

- Use case context as source of truth.
- Keep visible replies short.
- Ask at most one material clarifying question.
- Do not list every possible deliverable.
- Offer one next useful artifact at a time.
- Build structured work product behind the scenes.

When structured output is enabled, `AIEngine.autonomousCaseSystemDataPrompt` appends a required dual-output format:

```text
VISIBLE RESPONSE:
[short user-facing reply]

---
SYSTEM DATA (JSON):
{
  "claims": [],
  "evidence_detected": [],
  "timeline_events": [],
  "documents_to_generate": [],
  "strategy_notes": [],
  "coaching_notes": [],
  "decision_tree_pathways": [],
  "say_dont_say": [],
  "response_analysis": [],
  "suggested_deliverable": null,
  "strategy_trigger": false
}
```

Visible chat and structured JSON are intentionally separate.

## Case Context Prep

Before calling the model, `ConversationManager.buildAutonomousCaseContext(for:)` builds a compact case snapshot.

It pulls from:

- `CaseMemoryStore`
- existing `CaseAnalysis`
- cached strategy
- evidence files from `CaseTreeViewModel`
- timeline events from `CaseTreeViewModel`
- recent case messages
- current claims, damages, documents, filing locations, and next steps
- substantive user turn count

That context is passed into `AIEngine.chat(...)` so the model can reason from what the case already knows instead of asking duplicate intake questions.

## Structured Parsing

`ConversationManager.parseChatEnvelope(...)` is the main parser.

It does three things:

1. Splits visible text from `SYSTEM DATA (JSON):`.
2. Extracts and decodes the JSON using `ChatSystemDataEnvelope`.
3. Maps decoded fields into `CaseUpdatePayload`.

If JSON is missing or invalid, parsing falls back safely:

- visible response is still shown
- no structured payload is applied
- the app does not crash

This fallback is important because model output can occasionally be malformed.

## Typed Models

`CaseWorkflowModels.swift` contains the structured case payload types.

Main root model:

- `CaseUpdatePayload`

Important child models:

- `WorkflowEvidenceItem`
- `DocumentRequirement`
- `FilingInstruction`
- `StrategyNote`
- `CoachingPoint`
- `DecisionTreePathway`
- `SayDontSayGuidance`
- `ResponseAnalysis`
- `FollowUpQuestion`
- `ExtractedLegalFact`

Deliverable categories are represented by `StructuredDeliverableCategory`:

- `timeline`
- `evidence`
- `documents`
- `strategy`
- `coaching`
- `responses`
- `decisionTreePathways`
- `sayDontSay`

These types are the bridge between model JSON, local heuristics, and saved case artifacts.

## Structured Artifact Categories

The app supports these structured legal deliverables:

- Timeline
  - Chronological case events.

- Evidence
  - Evidence registry items, uploaded files, proof references.

- Documents
  - Document checklist, filing instructions, draftable filings/letters/forms.

- Strategy
  - Tactical notes, strengths, weaknesses, risks, next legal steps.

- Coaching
  - Conversation posture, how to present facts, what to gather next, how to stay on-message.

- Responses
  - Analysis of incoming letters, emails, denials, notices, agency/court messages, or opposing-party communications.

- Decision Tree Pathways
  - Multiple possible routes, such as filing, negotiation, mediation, evidence-first, wait-for-response, escalation.

- Say / Don't Say
  - Case-specific communication guidance, negotiation pitfalls, admissions to avoid, and side arguments that weaken leverage.

## Artifact Routing

Structured artifacts must route through `CaseTreeViewModel`.

The key method is:

```text
ConversationManager.syncStructuredPayload(_:into:)
```

Current routing:

- timeline events -> `CaseTreeViewModel.addTimelineEvent(...)`
- evidence -> `.evidence` via `upsertTextFile(...)`
- document checklist -> `.documents` via `upsertTextFile(...)`
- filing instructions -> `.documents` via `upsertTextFile(...)`
- strategy notes -> `.strategy` via `upsertTextFile(...)`
- coaching notes -> `.coaching` via `upsertTextFile(...)`
- decision tree pathways -> `.decisionTreePathways` via `upsertTextFile(...)`
- say/don't-say -> `.sayDontSay` via `upsertTextFile(...)`
- response analysis -> `.response` via `upsertTextFile(...)`

Do not create a separate local store for generated legal work product. The sidebar/workspace expects artifacts to live in the case tree.

## Offer Logic

The app should not offer every artifact at once.

`ConversationManager.bestDeliverableToOffer(...)` chooses one best next deliverable based on:

- explicit model suggestion: `suggested_deliverable`
- response-analysis intent
- generated structured payload contents
- strategy/document/evidence/timeline flags

Rough priority:

1. response analysis when incoming response intent is detected
2. explicit model suggestion
3. responses
4. say/don't-say
5. decision tree pathways
6. coaching
7. strategy
8. documents
9. evidence
10. timeline

`deliverableOfferText(...)` turns that category into a short visible offer, for example:

- "I can turn this into a timeline if you want."
- "I can map your strongest pathways from here if you want."
- "I can build a say / don't say sheet for this if you want."
- "I can analyze that response and save it in Responses..."

## Case Analysis Flow

The full case analysis path is separate from ordinary chat but feeds the same case state.

`AIEngine.analyzeCase(context:)` sends a complete case file into the model using `fullCaseAnalysisSystemPrompt`.

The full case context may include:

- prior case analysis
- case memory
- timeline
- evidence summaries
- voice/recording transcripts

The model returns structured sections:

- case summary
- potential claims
- estimated damages
- evidence needed
- timeline of events
- next steps
- documents to prepare
- where to file

`CaseAnalysisParser` turns that text into `CaseAnalysis`.

That analysis then supports:

- dashboard display
- future case context
- strategy generation
- confidence scoring
- document suggestions
- next-action recommendations

## Evidence Analysis Flow

Evidence analysis uses a stricter JSON-only prompt.

`AIEngine.analyzeEvidenceDocument(...)` asks the model to return:

- summary
- violations
- damages
- timeline events
- deadlines
- missing evidence

`EvidenceAnalysisEngine.parseModelResponse(...)` decodes the response into `EvidenceAnalysis`.

Evidence then feeds:

- evidence files
- timeline events
- deadlines
- case analysis refresh
- strategy and confidence engines

## Strategy and Confidence Flow

Strategy:

- `AIEngine.updateLitigationStrategy(...)`
- prompt asks for legal theories, strengths, weaknesses, evidence gaps, opposing arguments, settlement range, and litigation plan
- parsed into `LitigationStrategy`
- cached and surfaced in case context/workspace

Confidence:

- `AIEngine.evaluateConfidence(...)`
- evaluates claim strength, evidence strength, settlement probability, and litigation risk
- parsed into `CaseConfidence`

These are higher-level reasoning products built from the already collected case file.

## Memory and Background Updates

The system keeps case context alive across turns by combining:

- stored messages
- `CaseMemoryStore`
- case files
- case analysis
- evidence summaries
- timeline events
- cached strategy

After user and assistant turns, the app can update memory and enqueue background case reasoning so future replies are more case-aware.

This is why the assistant can say less in chat while still preparing more detailed work product behind the scenes.

## Important Design Rules

- Keep UI changes separate from legal logic changes.
- Keep visible assistant replies short.
- Save structured work product into case artifacts.
- Route artifacts through `CaseTreeViewModel`.
- Keep `CaseUpdatePayload` backward compatible where possible.
- Treat `AIEngine` as the only direct model-call layer.
- Treat `ConversationManager` as the chat orchestration layer.
- Treat `WorkspaceManager` as the composition root.
- Do not bypass local storage patterns with ad hoc stores.

## Debugging Guide

If chat is visible but artifacts are not saving:

1. Check `AIEngine.autonomousCaseSystemDataPrompt`.
2. Check whether the model returned `SYSTEM DATA (JSON):`.
3. Check `ConversationManager.jsonStringAfterSystemDataMarker(...)`.
4. Check `ConversationManager.parseChatEnvelope(...)`.
5. Check `CaseUpdatePayload` mapping.
6. Check `ConversationManager.syncStructuredPayload(...)`.
7. Check `CaseTreeViewModel.upsertTextFile(...)` or timeline/event helpers.

If the assistant is dumping too much into chat:

1. Check `guidedCaseChatSystemPrompt`.
2. Check `autonomousCaseSystemDataPrompt`.
3. Check `deliverableOfferText(...)`.
4. Check `maybeOfferNextDeliverable(...)`.

If the wrong artifact is offered:

1. Check `LegalSignalExtractor.detectSuggestedDeliverable(...)`.
2. Check `ConversationManager.bestDeliverableToOffer(...)`.
3. Check whether `suggested_deliverable` from the model is overriding local priority.

If a folder/sidebar artifact does not appear:

1. Check the `CaseSubfolder` mapping.
2. Check `syncStructuredPayload(...)`.
3. Check whether `upsertTextFile(...)` rejected empty content.
4. Check selected case id and selected workspace section.

## Current Mental Model

Think of Pocket Lawyer as three layers:

```text
User-facing layer
  SwiftUI views, chat bar, sidebar, workspace navigation

Orchestration layer
  ChatViewModel, ConversationManager, WorkspaceManager

Legal work-product layer
  CaseUpdatePayload, CaseAnalysis, EvidenceAnalysis, LitigationStrategy,
  CaseTreeViewModel, LocalCaseStorage
```

The assistant talks simply, but the system is constantly trying to turn that conversation into a usable case file.
