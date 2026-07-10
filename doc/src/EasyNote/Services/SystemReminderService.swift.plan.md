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
- EventKit authorization and fetch callbacks use a single-resume checked continuation with a 10-second timeout. Cancellation, timeout, and late callbacks cannot resume the continuation twice.
- Complete EventKit read-modify-write operations are serialized by the executor so actor reentrancy cannot create duplicate marker writes.
- Authorization status updates are published on the main actor; denied, restricted, timeout, missing-list, and EventKit system errors remain distinct.
- EventKit failures must remain separate from SwiftData save failures; a system reminder write error should not roll back a saved todo.

## Tests

- Unit tests exercise EventKit-adjacent behavior through `SystemReminderWritingProviding` and `SystemReminderEventStoreProviding` fakes, including timeout, late callback, cancellation, duplicate cleanup, and system errors.
- Manual smoke should verify real Reminders permission, create/update idempotency, complete, delete, and marker notes on a simulator or device with Reminders available.
