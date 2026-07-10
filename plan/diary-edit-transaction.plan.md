# Diary Edit Transaction

## Summary

- Make existing-diary editing transactional so Cancel truly discards content, mood, tag, transcription, and recording changes.
- Keep captured recordings retryable after save failure while protecting the original saved recording until SwiftData commits.

## Scope

- Add a pure `DiaryEditDraft` and shared `MoodCatalog` for edit state and stored mood labels.
- Route `DiaryEditView` through one explicit `DiaryViewModel.commitEditDraft` save boundary.
- Add focused unit tests and synchronize diary edit, speech, persistence, and acceptance documentation.
- Do not change the SwiftData schema, new-entry diary flows, AI provider behavior, or unrelated views.

## Implementation

- `DiaryEditDraft` snapshots the original persisted fields and owns mutable content, mood, tags, and an optional pending replacement audio URL.
- Content typing, mood/tag selection, transcription insertion/replacement, AI-refined transcription application, and recording capture update only the draft.
- Done commits all draft fields through one SwiftData save. Failed saves roll back, keep the editor open, retain the draft recording for retry, and show the persistence error.
- Discard removes only the pending replacement recording. Successful replacement removes the old saved recording only after SwiftData saves the new URL.
- `MoodCatalog` converts picker integers and legacy numeric strings to canonical Chinese stored labels while preserving existing non-empty Chinese labels.

## Test Plan

- Cover atomic save count, content/mood/tag/audio persistence, true discard, rollback, retry recording ownership, superseded pending recordings, mood compatibility, and transcription isolation before commit.
- Run `git diff --check`, Markdown relative-link sanity, `xcodebuild -list`, generic Debug/Release builds, and focused tests when a compatible simulator is available.

## Assumptions

- Existing numeric mood values are normalized only when an edited entry is explicitly saved; opening and canceling does not migrate data.
- Failed saves retain the pending recording because the visible draft remains available for retry.
- The editor does not persist from `onDisappear`; unresolved drafts are treated as discarded.
