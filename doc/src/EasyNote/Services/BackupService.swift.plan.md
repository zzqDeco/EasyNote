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
- Import validates the full backup before writing; failed import rolls back the `ModelContext` and removes newly restored audio files.

## Tests

- Unit tests cover encode/decode, export shape, audio export/restore, invalid backup rejection, no-write failure behavior, and upsert import behavior.
