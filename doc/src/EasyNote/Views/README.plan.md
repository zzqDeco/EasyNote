# Views Overview

## Responsibility

- Own SwiftUI presentation, navigation, user input, and local UI state for diary, todo, chat exploration, and settings screens.
- Keep app-wide theme and tab coordination visible through environment objects.

## Boundaries

- Do not build raw HTTP requests, manage audio engines, or implement CloudKit behavior inside views.
- Avoid creating fresh long-lived ViewModels inside `body`; prefer stable owners passed from `ContentView` or initialized once.

## Behavior Notes

- `ContentView` is the tab composition root.
- Diary views cover list, create, edit, detail, markdown, mood, and tag flows.
- Todo views cover recommendations, detail/edit, and unified add.
- Chat views cover AI exploration and persisted session selection.
- Settings owns local theme and DeepSeek API key entry.

## Tests

- UI test coverage is currently launch-level only.
- Add UI smoke tests only after the app has stable accessibility identifiers for primary flows.
