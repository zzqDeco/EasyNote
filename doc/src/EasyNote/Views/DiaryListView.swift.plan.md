# DiaryListView.swift

## Responsibility

- Present diary list/review modes, search/filter controls, deletion confirmation, and pull-to-refresh state.

## Boundaries

- Persistence and fetch behavior belongs to `DiaryViewModel`.
- Refresh callbacks must not mutate SwiftUI animation state outside the main actor.

## Behavior Notes

- Pull-to-refresh awaits the ViewModel reload and explicitly hops to `MainActor` before toggling the local refresh animation trigger.

## Tests

- Strict-concurrency builds cover callback isolation; UI smoke retains list navigation and filter coverage.
