# Todo Local Notifications

## Summary

- Add local reminder notifications for todos with deadlines.
- This slice improves the local-first todo workflow without changing SwiftData schema or enabling remote sync.

## Scope

- Add a pure notification planner for deciding whether a todo should have a pending local notification.
- Add a `UserNotifications` backed service for scheduling, canceling, and reconciling todo reminders.
- Inject the scheduler into `TodoViewModel` so todo create, edit, delete, complete, and recurring-next-item paths keep notifications in sync.
- Add Settings controls for the global todo reminder switch and notification permission state.
- Update README, interface docs, acceptance checks, and source notes.

Non-goals:

- Do not add per-todo reminder fields or change SwiftData models.
- Do not make UI tests depend on real notification permission prompts.
- Do not enable CloudKit or remote push notifications.

## Implementation

- Store the global toggle in `UserDefaults` with key `todo_notifications_enabled`.
- Use `TodoNotificationPlanner` to derive notification eligibility from existing todo fields:
  - incomplete todo
  - non-nil future deadline
- Use stable notification identifiers derived from `TodoItem.id`, so edits replace the same pending reminder and deletes/completion can cancel it.
- Add `TodoNotificationSchedulingProviding` to the existing service protocol boundary.
- `LocalTodoNotificationService` owns `UNUserNotificationCenter`, authorization status publishing, request authorization, pending reminder writes, and todo reminder cancellation.
- `TodoViewModel` synchronizes reminders only after SwiftData saves succeed. Failed saves must not schedule or cancel reminders for uncommitted state.
- `SettingsView` owns only user-facing controls: enable/disable, request permission, status text, and full todo reconciliation when notifications are enabled.

## Test Plan

- Unit tests:
  - eligible future incomplete todo produces a stable notification identifier.
  - completed, no-deadline, and past-deadline todos are not eligible.
  - adding a todo synchronizes its notification after a successful save.
  - editing a todo synchronizes the same todo notification after a successful save.
  - completing a todo cancels its notification.
  - completing a recurring todo cancels the original notification and synchronizes the generated next todo.
- Local checks:
  - `git diff --check`
  - `xcodebuild -list -project EasyNote.xcodeproj`
  - run simulator tests when a compatible runtime is available.
- CI:
  - hosted `EasyNoteTests` remains the blocking gate.

## Assumptions

- Local notifications are reminder conveniences, not persisted todo fields.
- Disabling reminders cancels pending todo notifications but does not change todo data.
- A future per-todo reminder customization PR can add schema and migration notes separately.
