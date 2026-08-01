# Chat SwiftData Rollback Recovery

## Summary

- Prevent chat save failures from leaving published SwiftData relationship objects in a corrupted rollback state.
- Preserve persisted sessions and pending request routing by rebuilding the UI context and rehydrating sessions by UUID.

## Scope

- Update `ChatSessionViewModel` save-failure recovery for new sessions, messages, titles, and clear-session operations.
- Add regression coverage for failed saves, retries, selection restoration, and in-flight provider responses.
- Do not change the SwiftData schema, chat response contract, or successful-save behavior.

## Implementation

- Capture session identifiers before mutating SwiftData; do not keep relationship collections as rollback snapshots.
- On save failure, roll back once, replace the `ModelContext` from the same container, preserve its autosave setting, and fetch fresh session objects.
- Restore the current selection by UUID without automatically creating or saving a replacement session during recovery.
- Keep request tasks keyed by captured request/session IDs so a context replacement cannot redirect a response.
- Preserve the original user-visible save error after rehydration.

## Test Plan

- Verify a failed user-message save does not start the provider, does not crash on relationship access, and can be retried.
- Verify failed title, clear-session, and new-session saves preserve persisted state and replace stale objects.
- Verify a pending response remains bound to its original session across another session's save failure.
- Run `git diff --check`, Markdown relative-link checks, `xcodebuild -list`, generic simulator build-for-testing, Release generic-device build, and the complete `EasyNoteTests` suite on the trusted physical iPhone.

## Assumptions

- The current `ModelContainer` remains valid when an individual context save fails.
- Existing pending provider tasks contain value-based request/session identifiers and may continue after rehydration.
- Simulator recreation is outside this slice; local runtime validation uses the paired physical iPhone.
