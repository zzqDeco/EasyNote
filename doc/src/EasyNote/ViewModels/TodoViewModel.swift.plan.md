# TodoViewModel.swift

## Responsibility

- Own todo SwiftData loading, create/update/delete/completion mutations, and reminder-output reconciliation after successful saves.
- Accept confirmed `TodoDraft` values at the todo creation boundary.

## Boundaries

- Do not persist unconfirmed view draft state.
- Do not treat notification or EventKit side-effect failure as a failed SwiftData save.

## Behavior Notes

- `addTodoItem(from:)` constructs and inserts a `TodoItem` only after the UI explicitly submits a draft.
- Mutation methods return `Bool`, roll back on save failure, and publish `errorMessage` for retained UI retry state.

## Tests

- Cover draft cancellation, save rollback, update/delete recovery, recurrence creation, and reminder routing through fakes.
