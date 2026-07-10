# Async Reminder Service Boundaries

## Summary

- Replace semaphore-backed reminder operations with cancellable async service contracts.
- Preserve todo persistence and reminder-mode behavior while surfacing reminder failures separately.

## Scope

- Change local-notification and system-Reminders protocols, production services, adapters, TodoViewModel reminder routing, Settings reminder actions, and focused tests.
- Keep reminder planning, SwiftData schema, reminder-mode migration, and user-visible mode choices unchanged.

## Implementation

- Use native async `UNUserNotificationCenter` APIs and injectable adapters so scheduling failures are testable.
- Bridge EventKit callbacks through a single-resume checked continuation; use a 10-second operation timeout and a separate five-minute authorization-prompt timeout, and ignore callbacks after completion, timeout, or cancellation.
- Serialize complete EventKit read-modify-write operations so concurrent writes preserve marker idempotency and duplicate cleanup.
- Distinguish denied/restricted authorization, timeout, missing default list, EventKit failures, and local notification scheduling failures.
- Keep SwiftData saves authoritative. Reminder side effects run afterward through owned tasks and publish errors on the main actor without rolling back saved todos.

## Test Plan

- Cover timeout, late callback, cancellation, EventKit error mapping, duplicate markers, missing default list, notification add failure, and persistence surviving reminder failure.
- Run project listing, test-target compilation, generic Debug/Release builds, Markdown link checks, secret scan, and `git diff --check`.
- Run focused tests on a compatible simulator when available; otherwise record the CoreSimulator mismatch and rely on hosted CI for execution.

## Assumptions

- EventKit operation timeout is 10 seconds in production; authorization uses a separate five-minute timeout. Both are injectable for tests.
- System Reminders continue using the default list and `EasyNoteTodoID:<uuid>` marker.
- Full ViewModel actor isolation remains part of the dedicated concurrency-isolation work; this slice confines reminder-result publication to main-actor tasks.
