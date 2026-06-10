# ViewModels Overview

## Responsibility

- Own UI-facing state, SwiftData fetch/save operations, service orchestration, and user-visible error state.
- Keep SwiftUI views focused on presentation and interactions.

## Boundaries

- Do not make ViewModels the long-term owner of provider-specific parsing or low-level audio/cloud APIs.
- Do not silently swallow core save failures; expose an error message or route through a documented fallback.

## Behavior Notes

- `DiaryViewModel` owns diary CRUD, current entry state, speech save integration, AI diary actions, and CloudKit entry points.
- `TodoViewModel` owns focused todo CRUD and recurrence.
- `ExploreViewModel` owns recommendation state and todo projection for the former Explore screen.
- `ChatSessionViewModel` owns persisted chat sessions and message history.
- `ChatSessionViewModel` can create a fallback local SwiftData context and must keep its `ModelConfiguration` compatible with the app-level local store contract.
- `ContentView` keeps stable app-level ViewModel instances and rebinds their `ModelContext` from the SwiftUI environment.

## Tests

- Current unit tests cover pure model behavior.
- Future ViewModel tests should introduce protocol-based service seams before asserting network, speech, or CloudKit behavior.
