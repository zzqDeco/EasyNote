# LocalTodoNotificationService.swift

## Responsibility

- Own iOS local notification permission state for todo reminders.
- Schedule, reconcile, and cancel pending todo reminder notifications through `UNUserNotificationCenter`.

## Boundaries

- Do not own todo CRUD or SwiftData saves.
- Do not decide reminder eligibility inline; use `TodoNotificationPlanner`.
- Do not expose `UNUserNotificationCenter` to ViewModels or SwiftUI views.
- Do not schedule remote push notifications.

## Behavior Notes

- Global enablement is read from `todo_notifications_enabled`.
- Scheduling first checks current system notification settings, then writes a one-shot calendar notification for eligible todos.
- Disabling reminders or making a todo ineligible cancels the stable todo notification identifier.
- Bulk cancellation is limited to identifiers with the EasyNote todo reminder prefix.

## Tests

- Service-level behavior is covered indirectly by project compilation.
- ViewModel unit tests use `TodoNotificationSchedulingProviding` fakes so CI does not require live notification permission prompts.
