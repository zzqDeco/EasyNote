# Local Core Reliability

## Summary

Tighten EasyNote's local-first persistence behavior before adding larger product features. This slice keeps the current UI and SwiftData schema, but makes ViewModel context binding, save failures, and recurring todo completion easier to reason about and test.

## Scope

- Update app-level ViewModel lifecycle so production views are rebound to the shared SwiftData `ModelContext` before user actions depend on them.
- Make diary and chat save paths report success or user-visible errors instead of fire-and-forget or log-only behavior.
- Extract recurring todo completion into a shared helper used by both todo entry points.
- Keep preview and test in-memory contexts available; do not enable real CloudKit or change persisted model fields.

## Implementation

- Keep `ContentView.bindModelContext()` as the production context handoff, and make the ViewModels safe to rebind without retaining a hidden production fallback store.
- Replace `DiaryViewModel.saveContext()` with a synchronous `Bool` result on the owning context and update diary mutations to set `errorMessage` when saving fails.
- Change `ChatSessionViewModel.saveContext()` to return `Bool`; only update session lists, current session, and message return values after a save succeeds.
- Add a shared `TodoRecurrencePlanner` that returns the next recurring `TodoItem` only when a completed item has a valid interval and deadline.
- Route `TodoViewModel` and `ExploreViewModel` recurring completion through that helper.

## Test Plan

- Add focused tests for recurring todo completion helper behavior:
  - completed recurring todo with valid deadline/interval creates an incomplete next todo
  - non-recurring todo creates no next todo
  - recurring todo without a deadline creates no next todo
  - recurring todo with an invalid interval creates no next todo
- Keep existing recurrence date and chat-session tests passing.
- Run `git diff --check` and `xcodebuild -list -project EasyNote.xcodeproj`.
- Rely on GitHub CI for `xcodebuild test -only-testing:EasyNoteTests` if the local simulator runtime remains unavailable.

## Assumptions

- This PR intentionally does not change the SwiftData schema.
- This PR does not attempt a large dependency-injection rewrite; it only narrows the unsafe lifecycle and save behavior.
- Preview-only fail-fast behavior remains acceptable when isolated to previews or in-memory helpers.
