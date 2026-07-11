# SwiftData Lifecycle

## Summary

- Replace fatal SwiftData startup with an explicit loading, ready, and failed lifecycle.
- Preserve the current persisted model layout while establishing the first versioned schema and a safe, user-confirmed recovery path.

## Scope

- Add `EasyNoteSchemaV1` and `EasyNoteMigrationPlan` without adding, removing, or changing persisted fields.
- Add an injectable persistence bootstrap for normal open, retry, recovery copy, and rebuild behavior.
- Copy the store and existing WAL/SHM sidecars into `Documents/EasyNoteRecovery/<timestamp>` before any confirmed rebuild removes store files.
- Add startup failure UI with retry and an explicitly confirmed recovery-copy-and-rebuild action.
- Explicitly delete every `SessionMessage` before deleting its `ChatSession`, and roll back the context if save fails.
- Replace meaningless random-UUID integrity checks with tests for actual title, content, and timestamp constraints.
- Keep CloudKit disabled at the app `ModelConfiguration` boundary and preserve the existing `EasyNote.store` location.
- Do not add model fields, inverse relationships, automatic reset behavior, CloudKit enablement, or parallel release-readiness documentation.

## Implementation

- `EasyNoteSchemaV1` lists the existing diary, todo, chat-session, and session-message models under version `1.0.0`; `EasyNoteMigrationPlan` contains V1 and no migration stages.
- `PersistenceBootstrap` owns `loading`, `ready(ModelContainer)`, and `failed` state. Its container factory, clock, and file operations are injectable for focused tests.
- Retry reopens the same store without modifying files. Recovery first copies every existing store component, aborts without deletion if copying fails, then removes the original components and attempts a fresh open.
- A failed rebuild remains user-visible and reports the recovery-copy location. Recovery is never triggered automatically.
- `ChatSessionViewModel.deleteSession` stages explicit message and session deletes in one `ModelContext`; its existing save seam drives success or rollback.

## Test Plan

- Cover existing-store open, startup failure followed by retry, recovery copies of store/WAL/SHM, and rebuild failure.
- Cover successful session deletion leaving no `SessionMessage` rows and failed deletion restoring both session and messages.
- Cover real chat integrity constraints: non-empty session title, non-empty message content, and non-future timestamps.
- Run `git diff --check`, Markdown link validation, `xcodebuild -list`, generic-simulator build-for-testing, Release generic-device build, and focused tests when a compatible simulator runtime is available.

## Assumptions

- The current `EasyNote.store` file format remains compatible because V1 uses the existing model classes unchanged.
- A recovery directory may remain after a failed copy or rebuild so diagnostics and copied data are not destroyed.
- Restoring a recovery copy in place is a separate manual support workflow; this slice guarantees preservation before rebuild but does not add an import UI for SQLite files.
