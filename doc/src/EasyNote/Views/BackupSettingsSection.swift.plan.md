# BackupSettingsSection.swift

## Responsibility

- Own Settings backup file exporter/importer presentation, preview state, confirmation, and user-visible result messages.
- Pass the supplied `ModelContext` to `BackupServiceProviding` for export and confirmed import.

## Boundaries

- Do not implement backup encoding, validation, merge rules, or audio restoration; those remain in `BackupService`.
- Do not alter `.easynotebackup` type registration or import notification semantics.

## Behavior Notes

- Export filenames keep the `EasyNoteBackup-yyyyMMdd-HHmmss` pattern.
- Import reads security-scoped file URLs, validates before confirmation, and shows entity/audio counts before writing.
- Successful import posts `easyNoteBackupDidImport` for active ViewModel reloads.
- Accessibility identifiers remain `settings.exportBackupButton` and `settings.importBackupButton`.

## Tests

- `BackupService` unit tests cover format and merge behavior; UI smoke covers the stable entry-point identifiers.
- App builds verify `FileDocument`, importer, exporter, and confirmation wiring.
