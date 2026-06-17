# Local Export Backup

## Summary

- Add a local-first backup and restore flow for diary entries, todo items, chat sessions, messages, and local voice recordings.
- This slice protects user data before future sync or larger refactors.

## Scope

- Add a Codable backup file contract and `BackupService`.
- Add Settings actions for exporting and importing backup files.
- Importing updates same-ID data and preserves local data absent from the backup.
- Non-goals: CloudKit sync, account-based restore, encrypted backups, and persistent backup history.

## Implementation

- Use a single JSON file with extension `.easynotebackup` and root type `EasyNoteBackupV1`.
- Store `version`, `exportedAt`, `diaryEntries`, `todoItems`, `chatSessions`, `sessionMessages`, and `audioAssets`.
- Export local `.caf` and `.m4a` diary recordings as base64 JSON data through `audioAssets`; diary entries reference recordings by `audioAssetId`.
- Export only chat messages referenced by exported chat sessions; orphaned messages from deleted sessions are not part of the user-visible backup.
- Validate the full backup before import. Reject unsupported versions, duplicate IDs, missing audio/message references, invalid audio metadata, or malformed JSON before writing SwiftData.
- Restore audio assets into the app Documents directory as `restored_recording_<uuid>.<ext>`.
- Upsert same-ID SwiftData records and keep local records that are not present in the backup, including newer local messages attached to an imported chat session.
- Roll back the `ModelContext` and remove newly restored audio files if import fails.
- Post `easyNoteBackupDidImport` after successful import so active ViewModels reload their local lists.

## Test Plan

- Unit tests cover DTO encode/decode, export data shape, audio export/restore, unsupported version, invalid audio base64, import upsert, orphaned message exclusion, blank title tolerance for app-created records, preserved local message timestamps, and failed-import no-write behavior.
- Local checks: `git diff --check`, `xcodebuild -list -project EasyNote.xcodeproj`, and simulator `xcodebuild test` when a compatible runtime is installed.
- PR CI must pass `EasyNoteTests`.
- Manual smoke: export a backup, inspect import preview counts, import into an app install with existing data, confirm same-ID records update, unrelated local records remain, and voice diary audio files are restored.

## Assumptions

- Backup v1 uses JSON with base64 audio instead of a zip/package format.
- Only `.caf` and `.m4a` local recording files are included.
- Import does not delete old local recording files that are no longer referenced after an overwrite; cleanup can be handled by a later maintenance plan.
