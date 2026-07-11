# BackupService.swift

## Responsibility

- Own the local backup v1 JSON contract for diary, todo, chat, message, and local recording data.
- Export SwiftData records and supported local audio files into a single `.easynotebackup` JSON file.
- Validate and import backups with upsert semantics.

## Boundaries

- Do not change SwiftData model fields in this service.
- Do not delete local records that are absent from an imported backup.
- Do not handle CloudKit, network sync, encryption, or account-level restore.
- Do not put Settings UI state or file picker state in this service.

## Behavior Notes

- Supported backup version is `1`.
- Supported audio extensions are `.caf` and `.m4a`.
- Audio assets are encoded as base64 JSON data and restored under Documents as `restored_recording_<uuid>.<ext>`.
- Exported chat messages must be reachable from exported chat sessions; orphaned `SessionMessage` records are not user-visible and are not included.
- Validation rejects a message ID referenced by more than one chat session because the SwiftData relationship has a single owning session.
- Import validates the full backup before writing; failed import rolls back the `ModelContext` and removes newly restored audio files.
- Import preserves local records absent from the backup, including existing messages attached to an imported session, without moving that session behind newer preserved messages in the session list.

## Tests

- Unit tests cover encode/decode, export shape, audio export/restore, invalid and cross-session message rejection, no-write failure behavior, upsert import behavior, orphaned message exclusion, app-compatible blank titles, and preserved local message timestamps.
