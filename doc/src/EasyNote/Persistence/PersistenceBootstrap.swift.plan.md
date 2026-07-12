# PersistenceBootstrap.swift

## Responsibility

- Own SwiftData container startup state, retry, recovery copy, and confirmed rebuild.
- Define injectable container, clock, and file-operation seams for lifecycle tests.

## Boundaries

- Never reset or remove a persistent store automatically.
- Do not place Settings JSON backup/import or CloudKit sync behavior in this boundary.

## Behavior Notes

- Production uses `Documents/EasyNote.store`, `EasyNoteSchemaV1` without a staged plan, and `cloudKitDatabase: .none`; this is the first-version adoption path for the identical legacy layout.
- Adoption or open failure enters the same failed state and never triggers automatic rebuild, deletion, or migration-plan fallback.
- Retry only reopens the same configuration.
- Rebuild first copies every existing store/WAL/SHM component into a unique UTC timestamp directory under `Documents/EasyNoteRecovery`.
- Copy failure leaves source files untouched. Rebuild failure keeps and reports the recovery directory.
- The injected dependency bundle is unchecked Sendable only to satisfy its static production default; it is created and consumed exclusively inside the main-actor `PersistenceBootstrap` boundary.

## Tests

- Cover existing-layout open, failed state and retry, all SQLite sidecars, copy-before-delete ordering, and rebuild failure.
