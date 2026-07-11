# BackupService.swift

## Responsibility

- Own the local backup v1 JSON contract for diary, todo, chat, message, and local recording data.
- Export SwiftData DTO snapshots and supported local audio files into a single `.easynotebackup` JSON file through an async boundary.
- Validate resource limits and import backups with transactional audio staging plus SwiftData upsert semantics.

## Boundaries

- Do not change SwiftData model fields in this service.
- Do not delete local records that are absent from an imported backup.
- Do not handle CloudKit, network sync, encryption, or account-level restore.
- Do not put Settings UI state or file picker state in this service.

## Behavior Notes

- Supported backup version is `1`.
- Supported audio extensions are `.caf` and `.m4a`.
- `BackupLimits.default` caps raw files at 64 MiB, one audio asset at 16 MiB, aggregate audio at 47 MiB to leave base64 envelope headroom, diaries at 10,000, todos at 50,000, sessions at 5,000, messages at 100,000, and audio assets at 500.
- Raw size is rejected before decode; decoded counts and audio limits are rejected before staging or SwiftData mutation.
- SwiftData snapshots and writes stay on `MainActor`; JSON and audio I/O run through detached work.
- Audio assets are encoded as base64 JSON data and staged before installation under deterministic Documents paths `restored_recording_<asset-id>.<ext>`.
- Exported chat messages must be reachable from exported chat sessions; orphaned `SessionMessage` records are not user-visible and are not included.
- Legacy messages referenced by multiple sessions are exported as independent backup message IDs with copied payloads, preserving every conversation while keeping the generated backup importable.
- Decode and import normalize shared references in older V1 files before strict validation, preserving V1 restore compatibility without recreating unsupported shared SwiftData relationships.
- Validation rejects any cross-session message reference that remains after compatibility normalization.
- Existing deterministic targets are copied into rollback storage before overwrite. Targets referenced by backup-external diaries are not overwritten and instead select a stable collision-safe path. File-commit or SwiftData-save failure restores prior files by move or atomic replacement without a second full copy and rolls back the `ModelContext`.
- Successful import cleans only direct, unreferenced Documents recordings with supported extensions and the backup-owned `restored_recording_` prefix. Recorder-owned `recording_` files are preserved because they may be unsaved drafts.
- Import preserves local records absent from the backup, including existing messages attached to an imported session, without moving that session behind newer preserved messages in the session list.
- Export preserves creation-date ordering by sorting fetched models in memory; custom date strategies use inline sendable closures without changing the V1 encoding format.

## Tests

- Unit tests cover every resource boundary, V1 fixture decode, encode/decode and export shape, background work, legacy shared-message normalization, deterministic repeated audio import, file/save rollback, safe orphan cleanup, invalid-reference no-write behavior, upsert behavior, orphaned message exclusion, app-compatible blank titles, and preserved local message timestamps.
