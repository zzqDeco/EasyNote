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
- `TodoViewModel` owns focused todo CRUD and recurrence.
- `ExploreViewModel` owns recommendation state and todo projection for the former Explore screen.
- `ChatSessionViewModel` owns persisted chat sessions and message history.
- `ChatSessionViewModel` uses an in-memory fallback context only when no context is injected.
- `ContentView` keeps stable app-level ViewModel instances by constructing them from the SwiftUI environment `ModelContext` in its root view.
- `TodoViewModel` and `ExploreViewModel` share the same recurrence planning helper for completed recurring todos.

## Tests

- Current unit tests cover pure model behavior.
- Future ViewModel tests should introduce protocol-based service seams before asserting network, speech, or CloudKit behavior.
