# PersistenceBootstrap.swift

## Responsibility

- Own SwiftData container startup state, retry, recovery copy, and confirmed rebuild.
- Define injectable container, clock, and file-operation seams for lifecycle tests.

## Boundaries

- Never reset or remove a persistent store automatically.
- Do not place Settings JSON backup/import or CloudKit sync behavior in this boundary.

## Behavior Notes

- Production uses `Documents/EasyNote.store`, `EasyNoteSchemaV1`, `EasyNoteMigrationPlan`, and `cloudKitDatabase: .none`.
- Retry only reopens the same configuration.
- Rebuild first copies every existing store/WAL/SHM component into a unique UTC timestamp directory under `Documents/EasyNoteRecovery`.
- Copy failure leaves source files untouched. Rebuild failure keeps and reports the recovery directory.

## Tests

- Cover existing-layout open, failed state and retry, all SQLite sidecars, copy-before-delete ordering, and rebuild failure.
