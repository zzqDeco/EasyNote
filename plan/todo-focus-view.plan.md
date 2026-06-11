# Todo Focus View

## Summary

- Turn the current mixed todo/recommendation screen into a focused task view with stable todo categories.
- Keep this slice local-first: no SwiftData schema changes, no CloudKit work, and no broad visual redesign.

## Scope

- Add a pure `TodoFilter` helper for today, overdue, upcoming, no-date, recurring, and completed projections.
- Update `ExploreView` to show a segmented todo filter and route todo completion, edit, delete, creation, and recommendation-to-todo actions through `TodoViewModel`.
- Remove duplicated todo CRUD ownership from `ExploreViewModel`; it should keep recommendation generation and cache responsibilities.
- Update architecture/source docs and MVP manual smoke coverage.

Non-goals:

- No new persistence fields or migration.
- No hosted UI-test expansion; UI smoke remains a later PR.
- No redesign of recommendation generation or AI parsing.

## Implementation

- Introduce `TodoFilter` under `EasyNote/Models/` with a pure `apply(to:calendar:now:)` method.
- Keep `Calendar.current` as the production default and inject `Calendar`/`now` in tests.
- `ExploreView` owns the selected filter state and renders the filtered `TodoViewModel.todoItems`.
- `ExploreViewModel` keeps diary fetches, recommendation generation, cached recommendation storage, and error/loading state only.
- Add a `TodoViewModel.addTodoItem(_:)` overload so the new-todo entry can insert the same object that is then edited.
- Keep recommendation-created todos at the existing default deadline of one hour after creation.

## Test Plan

- `TodoFilter` tests cover each category with representative todos.
- Tests assert completed todos are excluded from today, overdue, upcoming, and no-date filters.
- Tests assert recurring filter remains compatible with recurrence-created next todos.
- Local checks: `git diff --check`, `xcodebuild -list -project EasyNote.xcodeproj`, docs link sanity, and secret scan.
- Full unit tests rely on GitHub CI if the local simulator runtime remains unavailable.

## Assumptions

- The todo tab remains the existing `ExploreView` file for this slice; renaming the view/file can happen in a later cleanup.
- Recurring includes every recurring item regardless of completion state because the category is based on `isRecurring == true`.
- Recommendation-to-todo remains a one-click action with a default deadline one hour later.
