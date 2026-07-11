# TodoViewModel.swift

## Responsibility

- Own todo SwiftData loading, create/update/delete/completion mutations, and reminder-output reconciliation after successful saves.
- Accept confirmed `TodoDraft` values at the todo creation boundary.

## Boundaries

- Do not persist unconfirmed view draft state.
- Do not treat notification or EventKit side-effect failure as a failed SwiftData save.
- Keep published todo/reminder state and the SwiftData UI context on the main actor.

## Behavior Notes

- `addTodoItem(from:)` constructs and inserts a `TodoItem` only after the UI explicitly submits a draft.
- Mutation methods return `Bool`, roll back on save failure, and publish `errorMessage` for retained UI retry state.
- Reminder operations remain serialized through one main-actor task chain. Local notification reconciliation receives copied snapshots rather than the live SwiftData models.
- Unified logs contain only aggregate counts or static failure events.

## Tests

- Cover draft cancellation, save rollback, update/delete recovery, recurrence creation, reminder routing through fakes, and main-thread publication.
