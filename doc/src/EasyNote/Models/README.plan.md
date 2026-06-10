# Models Overview

## Responsibility

- Define SwiftData models and lightweight shared UI coordination models.
- Keep persisted model fields explicit and easy to reason about during prototype iteration.

## Boundaries

- Do not place network, speech, or CloudKit logic in models.
- Do not use models as a dumping ground for view-only formatting that belongs in views or helpers.

## Behavior Notes

- `DiaryEntry` owns diary content, metadata, optional audio URL, and AI summary.
- `TodoItem` owns recurrence through `RecurringInterval.rawValue` stored as `String`.
- `TodoRecurrencePlanner` owns pure next-todo creation rules for completed recurring todos.
- `ChatSession` owns session messages and generates short titles from the latest user message.
- `SessionMessage.relatedEntryIds` stores diary UUID strings instead of SwiftData relationships.
- `TabSelectionManager` is transient UI coordination and not a persisted domain object.

## Tests

- `EasyNoteTests` covers todo recurrence and chat-session summary/integrity.
- Add migration notes and tests before changing persisted fields or raw-value formats.
