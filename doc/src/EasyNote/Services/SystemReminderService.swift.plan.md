# SystemReminderService.swift

## Responsibility

- Own EventKit integration for writing EasyNote todos into Apple Reminders.
- Publish reminder authorization state and request full Reminders access.
- Apply, complete, and remove only reminders that carry the EasyNote todo marker.

## Boundaries

- Do not decide lead times or reminder eligibility here; that belongs to `SystemReminderAgent`.
- Do not read or write SwiftData; `TodoViewModel` owns persistence and calls this service only after successful saves.
- Do not schedule iOS local notifications; that remains `LocalTodoNotificationService`.
- Do not create a custom Reminders list in v1; use the system default list for new reminders.

## Behavior Notes

- The service uses EventKit `requestFullAccessToReminders` and requires `NSRemindersFullAccessUsageDescription`.
- Write-only Reminders access is treated as insufficient because EasyNote must read existing marker notes before update, complete, or delete operations.
- The v1 idempotency marker is `EasyNoteTodoID:<uuid>` appended to reminder notes.
- Applying a proposal updates the first matching marked reminder, creates one when none exists, and removes extra EasyNote-marked duplicates for the same todo.
- Completion and removal are no-op successes when the matching marked reminder is not found.
- EventKit work is serialized on a dedicated queue and completion/status updates return to the main thread.
- EventKit failures must remain separate from SwiftData save failures; a system reminder write error should not roll back a saved todo.

## Tests

- Unit tests should exercise EventKit-adjacent ViewModel behavior through `SystemReminderWritingProviding` fakes.
- Manual smoke should verify real Reminders permission, create/update idempotency, complete, delete, and marker notes on a simulator or device with Reminders available.
