# ReminderSettingsSection.swift

## Responsibility

- Own reminder-mode presentation, permission/status state, foreground refresh, and cancellable Settings reminder tasks.
- Coordinate existing local-notification, system-reminder agent/writer, mode-store, and SwiftData todo boundaries.

## Boundaries

- Do not duplicate notification eligibility, retained-slot selection, system-reminder proposal, EventKit, or persistence rules.
- Do not change reminder defaults keys, mutual-exclusion behavior, or permission-prompt policy.

## Behavior Notes

- `todo_notifications_enabled` remains synchronized with `TodoReminderModeStore` for legacy compatibility.
- Switching modes preserves the existing cancellation, reconciliation, immediate system sync, and stale-system-reminder cleanup ordering.
- Authorization publisher updates and foreground refresh retain separate status and write tasks so refresh does not cancel an active write.
- SwiftData fetches sort in main-actor memory, and local-notification reconciliation uses the shared `Sendable` todo snapshot bridge before awaiting the scheduler.
- Permission/sync button identifiers and `settings.todoReminderModePicker` remain unchanged.

## Tests

- Existing planner, service, mode-store, and ViewModel tests cover the coordination inputs.
- App build and UI smoke cover section bindings and stable accessibility identifiers; live permission prompts remain manual-only.
