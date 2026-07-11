# PersistenceFeedback.swift

## Responsibility

- Convert a ViewModel persistence result into a screen-dismissal decision and visible error message.

## Boundaries

- Do not perform persistence, mutate ViewModels, or navigate directly.
- Keep operation-specific fallback text at the call site.

## Behavior Notes

- Success requests dismissal and clears stale error text.
- Failure never requests dismissal and prefers the ViewModel error over the fallback.

## Tests

- Cover save and delete failure decisions plus the success path.
