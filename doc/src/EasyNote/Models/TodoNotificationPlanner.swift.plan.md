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

## Tests

- Unit tests cover eligible future todos, completed/no-deadline/past-deadline rejection, and identifier stability.
