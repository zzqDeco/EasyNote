# Agent System Reminders

## Summary

- Add a higher-level todo reminder mode that lets an agent runtime write eligible todos into the user's Apple Reminders app.
- This slice keeps PR #19 local notifications intact while preventing duplicate reminder systems by routing todo reminders through one active mode: off, EasyNote local notification, or system Reminders agent.

## Scope

- Add `TodoReminderMode` and a `UserDefaults` backed mode store with compatibility for the existing `todo_notifications_enabled` flag.
- Add a deterministic `SystemReminderAgent` that converts todo semantics, deadline, priority, and notes into a system reminder proposal.
- Add an EventKit-backed `SystemReminderService` behind `SystemReminderWritingProviding`.
- Integrate system reminder writes into `TodoViewModel` only after successful SwiftData saves.
- Update Settings to expose the reminder mode, system Reminders authorization state, and manual sync action.
- Update README, architecture, interface, acceptance, and source-boundary docs.

Non-goals:

- Do not change SwiftData schema or add per-todo reminder fields.
- Do not introduce LLM-based planning in v1; the agent is deterministic and testable.
- Do not create a custom Reminders list; v1 writes to the default list for new reminders.
- Do not bulk-delete existing system reminders when the mode is turned off.
- Do not enable CloudKit or remote push notifications.

## Implementation

- `TodoReminderMode` stores `off`, `localNotification`, or `systemReminderAgent` in `todo_reminder_mode`.
- When `todo_reminder_mode` is missing and `todo_notifications_enabled` is true, the mode store reports `.localNotification` so existing users keep their PR #19 behavior.
- Setting `.localNotification` writes `todo_notifications_enabled = true`; setting `.off` or `.systemReminderAgent` writes it to false.
- `SystemReminderAgent` returns a `SystemReminderProposal` with either `.createOrUpdate` or `.skip(reason)`.
- The agent skips completed todos, missing deadlines, non-future deadlines, titles that trim to empty, and deadlines less than 60 seconds away.
- Agent lead-time rules:
  - meeting/call keywords: 30 minutes
  - travel keywords: 2 hours
  - submission/deadline keywords: 24 hours when the deadline is more than 24 hours away, otherwise 2 hours
  - preparation keywords: 1 hour
  - default: 15 minutes
- If a semantic lead time would put the alarm in the past, the alarm clamps to `now + 60 seconds` when the deadline is still far enough away.
- EventKit reminders are identified by an `EasyNoteTodoID:<uuid>` marker appended to notes, avoiding any SwiftData schema changes.
- `SystemReminderService` requests full reminder access, finds existing marked reminders, updates one matching reminder, removes duplicate EasyNote-marked reminders for the same todo, and writes due date, alarm, priority, title, and notes.
- `TodoViewModel` writes system reminders only in `.systemReminderAgent` mode and only after SwiftData saves succeed.
- System reminder write failures do not roll back SwiftData saves; they set `systemReminderErrorMessage`.
- `SettingsView` switches modes, requests Reminders access, cancels local EasyNote notifications when entering system mode, and exposes a manual sync for current todos.

## Test Plan

- Unit tests:
  - completed, missing-deadline, past-deadline, too-close, and disabled-mode todos skip.
  - meeting, travel, submission, preparation, and default todos produce expected alarm dates and Chinese reason strings.
  - marker format equals `EasyNoteTodoID:<uuid>`.
  - adding, editing, completing, recurring-completing, and deleting todos call the fake system reminder writer in system mode.
  - local/off modes do not call the system reminder writer.
  - SwiftData save failure prevents system reminder writes.
  - writer failure sets `systemReminderErrorMessage` without removing the saved todo.
  - mode store migrates the legacy local-notification flag and updates that flag on mode changes.
- Local checks:
  - `git diff --check`
  - `xcodebuild -list -project EasyNote.xcodeproj`
  - `xcodebuild build-for-testing -project EasyNote.xcodeproj -scheme EasyNote -destination 'generic/platform=iOS Simulator'`
  - secret scan
  - Markdown relative link sanity check
- CI:
  - GitHub hosted unit tests remain the blocking PR gate.
- Manual smoke:
  - switch Settings to system Reminders mode
  - grant Reminders permission
  - create, edit, complete, and delete a deadline todo
  - confirm the Apple Reminders app has one EasyNote-marked reminder that updates instead of duplicating

## Assumptions

- Deployment target is iOS 18.2, so v1 uses `requestFullAccessToReminders` and `NSRemindersFullAccessUsageDescription`.
- The default Reminders list exists for normal production use; missing default list becomes a user-visible system reminder error.
- LLM-assisted reminder planning can be added later behind `SystemReminderAgentProviding` without changing EventKit writes.
- System Reminders mode supersedes EasyNote local notifications to avoid duplicate alerts.
