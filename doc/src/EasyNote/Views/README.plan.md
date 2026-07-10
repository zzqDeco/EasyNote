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
- Chat views cover AI exploration and persisted session selection; they construct immutable request snapshots and render processing/failure state for the selected session without owning network tasks.
- Settings owns local theme and DeepSeek API key entry.

## Tests

- UI smoke coverage uses stable accessibility identifiers for non-destructive tab navigation and setup controls.
- Unit tests cover `DiaryReviewProjection` and AI result confirmation helpers; manual smoke should verify diary review entry, empty state, filter independence, AI apply/copy/discard, and no accidental diary-body mutation.
- Do not add hosted blocking UI test expectations until runner stability has been proven.
