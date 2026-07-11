# EasyNoteSchema.swift

## Responsibility

- Define `EasyNoteSchemaV1` and the ordered `EasyNoteMigrationPlan` used by production and UI-test containers.
- Preserve explicit schema-version history as SwiftData models evolve.

## Boundaries

- V1 must retain the existing persisted model types and fields unchanged.
- Add a new schema version and documented migration stage before changing persisted layout; do not rewrite V1.

## Behavior Notes

- V1 is version `1.0.0` and contains `DiaryEntry`, `TodoItem`, `ChatSession`, and `SessionMessage`.
- The migration plan currently has no stages because there is only one unchanged schema version.

## Tests

- Open a store created with the pre-versioned model layout through the V1 bootstrap and verify existing data remains readable.
- Run simulator and generic-device compilation after schema or migration-plan changes.
