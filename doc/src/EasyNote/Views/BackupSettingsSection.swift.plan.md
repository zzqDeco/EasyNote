# BackupSettingsSection.swift

## Responsibility

- Own Settings backup file exporter/importer presentation, preview state, confirmation, and user-visible result messages.
- Await the supplied `BackupServiceProviding` for export, off-main file loading/validation, and confirmed import while passing `ModelContext` only to main-actor service operations.

## Boundaries

- Do not implement backup encoding, validation, merge rules, or audio restoration; those remain in `BackupService`.
- Do not alter `.easynotebackup` type registration or import notification semantics.

## Behavior Notes

- Export filenames keep the `EasyNoteBackup-yyyyMMdd-HHmmss` pattern.
- Import keeps security-scoped file access active while the async service checks raw size, reads, decodes, and validates before confirmation.
- Export and import buttons are disabled while one backup operation is active.
- Successful import posts `easyNoteBackupDidImport` for active ViewModel reloads.
- Accessibility identifiers remain `settings.exportBackupButton` and `settings.importBackupButton`.

## Tests

- `BackupService` unit tests cover format and merge behavior; UI smoke covers the stable entry-point identifiers.
- App builds verify `FileDocument`, importer, exporter, and confirmation wiring.
