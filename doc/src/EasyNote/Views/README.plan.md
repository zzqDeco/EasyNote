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
- Diary review UI is read-only and consumes `DiaryReviewProjection` from the full diary dataset rather than the active search/filter result.
- Diary transcription UI should present insert/replace actions explicitly; it should not mutate diary body text through implicit notifications.
- Todo views cover recommendations, detail/edit, and unified add.
- Chat views cover AI exploration and persisted session selection.
- Settings owns local theme and DeepSeek API key entry.

## Tests

- UI smoke coverage uses stable accessibility identifiers for non-destructive tab navigation and setup controls.
- Unit tests cover `DiaryReviewProjection`; manual smoke should verify diary review entry, empty state, and independence from active filters.
- Do not add hosted blocking UI test expectations until runner stability has been proven.
