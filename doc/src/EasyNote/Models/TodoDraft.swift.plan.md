# TodoDraft.swift

## Responsibility

- Hold todo title, priority, deadline, notes, and recurrence input before persistence.
- Normalize optional notes and recurrence values at the ViewModel submission boundary.

## Boundaries

- Do not conform to SwiftData `PersistentModel` or insert a `TodoItem`.
- Keep save, reminder, and navigation behavior in ViewModels and views.

## Behavior Notes

- Initializing or mutating a draft has no persistence side effect.
- Existing todo values, including legacy recurrence strings, can initialize an edit draft through the shared parser.

## Tests

- Verify canceling an unsubmitted draft leaves SwiftData empty.
- Verify legacy recurrence values initialize the expected recurrence selection.
