# EasyNoteSchema.swift

## Responsibility

- Define the frozen `EasyNoteSchemaV1` model ownership and the ordered `EasyNoteMigrationPlan` used after first-version adoption and by future versions.
- Preserve explicit schema-version history as SwiftData models evolve.

## Boundaries

- The top-level `DiaryEntry`, `TodoItem`, `ChatSession`, and `SessionMessage` storage types are the immutable V1 contract and must retain their persisted entity names, fields, and relationships.
- Add a new schema version and documented migration stage before changing persisted layout; do not rewrite V1.

## Behavior Notes

- V1 is version `1.0.0` and registers the existing top-level storage types. They remain top-level to preserve legacy entity identity and SwiftData relationship/rollback behavior.
- The migration plan currently has no stages because there is only one unchanged schema version.

## Tests

- Create a store with separate pre-versioned fixture models, assert its entity names match V1, adopt it with V1 and no plan, then reopen with `EasyNoteMigrationPlan` and verify existing data remains readable.
- Run simulator and generic-device compilation after schema or migration-plan changes.
