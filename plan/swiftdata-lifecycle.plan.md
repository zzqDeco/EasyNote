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
- Reject backup payloads that assign one `SessionMessage` ID to multiple sessions before any SwiftData write.
- Replace meaningless random-UUID integrity checks with tests for actual title, content, and timestamp constraints.
- Keep CloudKit disabled at the app `ModelConfiguration` boundary and preserve the existing `EasyNote.store` location.
- Do not add model fields, inverse relationships, automatic reset behavior, CloudKit enablement, or parallel release-readiness documentation.

## Implementation

- `EasyNoteSchemaV1` registers the existing top-level diary, todo, chat-session, and session-message storage types under version `1.0.0`. A frozen fixture and schema-signature test enforce the V1 layout because Xcode 16.4 crashes when relationship-bearing nested versioned models are rolled back.
- The current release opens V1 without a staged migration plan so an identical pre-versioned store can be adopted and stamped non-destructively. `EasyNoteMigrationPlan` remains defined with V1 and no stages for stores that have completed adoption and for future V2 work.
- `PersistenceBootstrap` owns `loading`, `ready(ModelContainer)`, and `failed` state. Its container factory, clock, and file operations are injectable for focused tests.
- Retry reopens the same store without modifying files. Recovery first copies every existing store component, aborts without deletion if copying fails, then removes the original components and attempts a fresh open.
- A failed rebuild remains user-visible and reports the recovery-copy location. Recovery is never triggered automatically.
- `ChatSessionViewModel.deleteSession` stages explicit message and session deletes in one `ModelContext`; on save failure it explicitly cancels those staged deletes and restores the relationship because Xcode 16.4 crashes when `ModelContext.rollback()` snapshots a versioned relationship delete.

## Test Plan

- Cover a plain-schema legacy store opening with V1, retaining data, and then reopening with `EasyNoteMigrationPlan`; verify legacy and V1 entity names match.
- Cover existing-store open, startup failure followed by retry, recovery copies of store/WAL/SHM, and rebuild failure.
- Cover successful session deletion leaving no `SessionMessage` rows and failed deletion restoring both session and messages.
- Cover real chat integrity constraints: non-empty session title, non-empty message content, and non-future timestamps.
- Run `git diff --check`, Markdown link validation, `xcodebuild -list`, generic-simulator build-for-testing, Release generic-device build, and focused tests when a compatible simulator runtime is available.

## Assumptions

- The current `EasyNote.store` file format remains compatible because V1 freezes the same entity names, fields, and relationships as the pre-versioned model layout.
- A recovery directory may remain after a failed copy or rebuild so diagnostics and copied data are not destroyed.
- Restoring a recovery copy in place is a separate manual support workflow; this slice guarantees preservation before rebuild but does not add an import UI for SQLite files.
