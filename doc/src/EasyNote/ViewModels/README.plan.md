# ViewModels Overview

## Responsibility

- Own UI-facing state, SwiftData fetch/save operations, service orchestration, and user-visible error state.
- Keep SwiftUI views focused on presentation and interactions.

## Boundaries

- Do not make ViewModels the long-term owner of provider-specific parsing or low-level audio/cloud APIs.
- Do not silently swallow core save failures; expose an error message or route through a documented fallback.
- Production ViewModels should receive the app's shared SwiftData `ModelContext`; nil-context fallback stores are for previews, tests, or explicitly degraded states only.

## Behavior Notes

- `DiaryViewModel` owns diary CRUD, current entry state, speech save integration, AI diary actions, and CloudKit entry points.
- `DiaryViewModel` mirrors speech permission state and keeps transcription/AI-refined text separate from diary body content until the user explicitly inserts or replaces it.
- `DiaryViewModel` records current-session AI action history and per-target/source pending AI results; diary summaries and transcription AI outputs require explicit apply before mutating `DiaryEntry.aiSummary` or `transcribedText`.
- `DiaryViewModel` binds pending diary summary results to their source `DiaryEntry.id` and removes discarded pending results from current-session history.
- `DiaryViewModel` clears stale pending results when a later AI action fails in the same target/source scope.
- `DiaryViewModel` rejects pending diary summary or transcription results when the source text fingerprint no longer matches the current text, including editor-content AI results whose source must be the current editor body rather than a copied transcription buffer.
- `DiaryViewModel` snapshots diary summary input before sending the AI request and uses that same snapshot for the result fingerprint.
- `DiaryViewModel` runs refined-content analysis after the user applies an accepted transcription `.refine` result, preserving mood/tag suggestions without analyzing discarded output.
- `DiaryViewModel` clears pending transcription AI results when the transcription buffer is reset or replaced, or when a new recording attempt starts; accepted editor-content results become the active transcription buffer for follow-up AI actions.
- `DiaryViewModel` owns cleanup helpers for captured local `.caf` diary recordings and legacy `.m4a` recordings so draft cancellation, existing-entry replacement, and deletion do not leave unreachable files.
- `DiaryViewModel` consumes AI, speech, and CloudKit behavior through service protocols with production defaults, so tests can inject fakes without invoking provider, microphone, or cloud paths.
- `DiaryViewModel.entries` is derived from the full `diaryEntries` source list through `DiaryEntryQuery`; search and filters must not overwrite the source list.
- `TodoViewModel` owns focused todo CRUD, recurrence, todo list state, and post-save reminder routing through injected local-notification and system-reminder services.
- `ExploreViewModel` owns recommendation generation, cached recommendation state, current-session recommendation AI history, and shared user-facing recommendation error mapping through the AI service protocol.
- `ChatSessionViewModel` owns persisted chat sessions and message history.
- `ChatSessionViewModel` uses an in-memory fallback context only when no context is injected.
- `ContentView` keeps stable app-level ViewModel instances by constructing them from the SwiftUI environment `ModelContext` in its root view.
- Todo filtering belongs to the pure `TodoFilter` helper, not to `ExploreViewModel`.
- Todo recurrence planning belongs to `TodoRecurrencePlanner` and is invoked from `TodoViewModel`.
- Todo local notification scheduling belongs to `TodoNotificationSchedulingProviding`; `TodoViewModel` reconciles local reminders only after SwiftData saves succeed, and deletion also cancels the removed todo identifier before reconciling the remaining list.
- Todo system Reminders writes belong to `SystemReminderAgentProviding` and `SystemReminderWritingProviding`; `TodoViewModel` applies, completes, or removes system reminders only in `.systemReminderAgent` mode and only after SwiftData saves succeed.
- System reminder write failures set `systemReminderErrorMessage` without rolling back the saved todo.

## Tests

- Current unit tests cover pure model behavior and AI result apply helpers.
- ViewModel tests should use protocol-based service fakes before asserting network, speech, CloudKit, notification, or EventKit-adjacent behavior.
