# Backup Resource Lifecycle

## Summary

- Bound local backup memory, storage, and SwiftData work while keeping backup V1 readable without changing its fields or file extension.
- Make import audio restoration repeatable and transactional so file state stays aligned with the SwiftData save result.

## Scope

- Add configurable default limits for raw files, entity counts, and embedded audio resources.
- Make backup export, encoding, decoding, file loading, and import async; keep SwiftData snapshot and mutation work on `MainActor` and move JSON/audio I/O off the main thread.
- Stage deterministic restored recording files, preserve overwritten files for rollback, and clean only unreferenced EasyNote-managed recordings after a successful save.
- Update the Settings backup flow, service protocol, focused tests, backup contract docs, source notes, acceptance criteria, and indexes.
- Do not change `EasyNoteBackupV1` fields, `.easynotebackup`, SwiftData models, AI credential/consent behavior, or speech/concurrency implementation files.

## Implementation

- Introduce `BackupLimits.default` with a 64 MiB raw file limit, 16 MiB per audio asset, 47 MiB total audio with base64 envelope headroom, and count limits of 10,000 diaries, 50,000 todos, 5,000 sessions, 100,000 messages, and 500 audio assets.
- Reject oversized raw data before JSON decode, then validate entity counts, audio byte declarations, per-asset bytes, aggregate audio bytes, references, extensions, and identifiers before any SwiftData or destination-file mutation.
- Snapshot model values and relationships on `MainActor`; perform audio reads and JSON encode/decode through detached work.
- Restore each audio asset through a temporary staging directory to `restored_recording_<asset-id>.<ext>`. When that path belongs to a backup-external diary, use a stable `_imported` collision suffix. Preserve prior destinations in rollback storage before overwrite, move or atomically replace them back when staging/commit or SwiftData save fails, and remove transaction storage after completion.
- After a successful save, enumerate direct Documents children and remove only unreferenced `.caf`/`.m4a` files with EasyNote recording prefixes. Preserve arbitrary user files, directories, and referenced recordings.

## Test Plan

- Cover exact-limit acceptance and one-over rejection for raw file size, every entity count, single-audio bytes, and total-audio bytes.
- Cover background JSON/audio work, V1 fixture compatibility, repeated deterministic import, staging/commit failure, SwiftData save failure with filesystem rollback, and safe post-save orphan cleanup.
- Run `git diff --check`, Xcode project listing, generic simulator build-for-testing, Release generic-device build, Markdown relative-link validation, and a repository secret scan.

## Assumptions

- EasyNote-managed recording files are direct children of Documents with supported audio extensions and names beginning with `recording_` or `restored_recording_`.
- Local records absent from an import remain preserved; cleanup applies only to managed recording files no longer referenced by any `DiaryEntry` after a successful import.
- Compatible simulator test execution may remain blocked by the local CoreSimulator/Xcode runtime mismatch; generic builds and hosted CI remain source-level authorities in that case.
