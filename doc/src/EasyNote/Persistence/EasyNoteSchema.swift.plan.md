# EasyNoteSchema.swift

## Responsibility

- Define the frozen `EasyNoteSchemaV1` model ownership and the ordered `EasyNoteMigrationPlan` used after first-version adoption and by future versions.
- Preserve explicit schema-version history as SwiftData models evolve.

## Boundaries

- V1 must retain the existing persisted entity names, fields, and relationships unchanged through version-owned nested model definitions and file-scope app-facing aliases.
- Add a new schema version and documented migration stage before changing persisted layout; do not rewrite V1.

## Behavior Notes

- V1 is version `1.0.0` and owns nested `DiaryEntry`, `TodoItem`, `ChatSession`, and `SessionMessage` definitions; existing source files expose aliases with the same app-facing names.
- The migration plan currently has no stages because there is only one unchanged schema version.

## Tests

- Create a store with separate pre-versioned fixture models, assert its entity names match V1, adopt it with V1 and no plan, then reopen with `EasyNoteMigrationPlan` and verify existing data remains readable.
- Run simulator and generic-device compilation after schema or migration-plan changes.
