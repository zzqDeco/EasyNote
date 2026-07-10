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
- Scheduling first checks current system notification settings, then writes a one-shot calendar notification for eligible todos through native async UserNotifications APIs.
- Scheduling uses per-todo versions so async writes cannot re-add reminders after a later cancel, completion, deletion, or global disable.
- `UNUserNotificationCenter.add` errors are surfaced as `TodoNotificationError.schedulingFailed`; after a successful add the service re-checks the schedule version and removes stale requests.
- Replacing a scheduled reminder removes both pending and delivered notifications for the stable todo identifier before adding the new request.
- When authorization is unavailable, the service removes the stable identifier instead of leaving stale pending requests behind.
- The service installs itself as `UNUserNotificationCenterDelegate` and opts EasyNote todo reminders into foreground banner/sound presentation.
- Disabling reminders or making a todo ineligible cancels the stable todo notification identifier.
- Reconciliation schedules only the retained reminder slots selected by `TodoNotificationPlanner` and cancels non-retained todo reminder identifiers.
- Bulk cancellation is limited to identifiers with the EasyNote todo reminder prefix and is guarded by a cancellation generation so stale enumeration callbacks cannot remove newly rescheduled reminders.

## Tests

- An injectable `UserNotificationCenterProviding` adapter covers add failures without live permission prompts.
- ViewModel unit tests use `TodoNotificationSchedulingProviding` fakes so CI does not require live notification permission prompts.
