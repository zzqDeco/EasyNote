# Views Overview

## Responsibility

- Own SwiftUI presentation, navigation, user input, and local UI state for diary, todo, chat exploration, and settings screens.
- Keep app-wide theme and tab coordination visible through environment objects.

## Boundaries

- Do not build raw HTTP requests, manage audio engines, or implement CloudKit behavior inside views.
- Avoid creating fresh long-lived ViewModels inside `body`; prefer stable owners passed from `ContentView` or initialized once.

## Behavior Notes

- `ContentView` is the tab composition root.
- Primary navigation, diary search/filter/add, todo focus, and Settings API key controls expose stable accessibility identifiers for local UI smoke tests.
- Diary views cover list, create, edit, detail, review insights, markdown, mood, and tag flows.
- Existing-diary edit UI owns a local `DiaryEditDraft`; typing, mood/tag changes, transcription, AI-refined text, and recordings do not mutate SwiftData until Done succeeds, while Cancel truly discards them.
- Diary review UI is read-only, consumes `DiaryReviewProjection` from the full diary dataset rather than the active search/filter result, and keeps bottom scroll padding for the tab-level floating add button.
- Diary transcription UI should present AI apply/copy/discard controls and insert/replace actions explicitly; it should not mutate diary body text through implicit notifications.
- Diary detail UI should show pending AI summaries before they are applied to the persisted summary field, scoped to the diary entry that produced the summary.
- Todo views cover recommendations, detail/edit, and unified add; todo list and detail surfaces display system reminder success/error messages published by `TodoViewModel`.
- Todo create/edit views bind to `TodoDraft`; Cancel never inserts a placeholder, and failed create/update/delete actions keep the active screen visible with an error.
- Diary create/edit/detail-delete views dismiss only after their ViewModel mutation succeeds and preserve retryable input on failure.
- `KeyboardObserver` owns exact cancellable keyboard notification subscriptions for views that need keyboard lifecycle state; repeated appearance must not duplicate subscriptions.
- Chat views cover AI exploration and persisted session selection; they construct immutable request snapshots and render processing/failure state for the selected session without owning network tasks.
- `SettingsView` only composes the form and forwards environment/dependency values; appearance, DeepSeek Keychain/consent, reminder, backup, and sync-preflight UI state belongs to dedicated Settings sections.
- Diary audio delegate completion and playback progress callbacks explicitly return to the main actor before mutating SwiftUI state.
- Diary pull-to-refresh performs its animation-state mutation inside an explicit main-actor hop.
- View diagnostics use categorized unified logging with static events; user-visible diary errors and audio paths are not copied into logs.

## Tests

- UI smoke coverage uses stable accessibility identifiers for non-destructive tab navigation and setup controls.
- Unit tests cover `DiaryReviewProjection` and AI result confirmation helpers; manual smoke should verify diary review entry, empty state, filter independence, AI apply/copy/discard, and no accidental diary-body mutation.
- Do not add hosted blocking UI test expectations until runner stability has been proven.
