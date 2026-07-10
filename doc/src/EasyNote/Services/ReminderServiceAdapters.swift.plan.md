# ReminderServiceAdapters.swift

## Responsibility

- Isolate UserNotifications and EventKit APIs behind injectable adapters.
- Provide the single-resume callback bridge used for EventKit timeout and cancellation safety.

## Boundaries

- Do not decide todo eligibility, agent lead time, reminder mode, or SwiftData behavior.
- Keep the EventKit snapshot limited to fields required for marker matching and existing-item selection.

## Behavior Notes

- Production EventKit authorization and fetch callbacks have a 10-second timeout supplied by `SystemReminderService`.
- The continuation gate resolves exactly once; timeout tasks are canceled after an earlier result, and callback results arriving after timeout or cancellation are ignored.
- The EventKit adapter maps reminder snapshots, writes proposal fields, and updates/removes records selected by the serialized service executor.
- The UserNotifications adapter uses native async settings, permission, pending/delivered lookup, and add APIs.

## Tests

- Fakes can withhold and release callbacks, return system errors, omit the default list, or fail notification adds without accessing live device services.
