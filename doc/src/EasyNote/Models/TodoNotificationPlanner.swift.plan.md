# TodoNotificationPlanner.swift

## Responsibility

- Provide pure local-notification eligibility and identifier rules for `TodoItem`.
- Keep reminder decisions derived from current todo fields instead of adding persisted reminder state.

## Boundaries

- Do not import `UserNotifications` or read `UserDefaults`.
- Do not mutate `TodoItem` or perform scheduling side effects.
- Do not encode permission or Settings UI behavior here.

## Behavior Notes

- A todo is eligible only when it is incomplete and has a future `deadline`.
- Notification identifiers use the stable `easynote.todo.<uuid>` prefix and `TodoItem.id`.
- Reconciliation keeps at most 64 retained reminder slots, sorted by nearest future deadline with stable creation date and UUID tie-breakers.

## Tests

- Unit tests cover eligible future todos, completed/no-deadline/past-deadline rejection, identifier stability, and nearest-deadline retention when more than 64 todos are eligible.
