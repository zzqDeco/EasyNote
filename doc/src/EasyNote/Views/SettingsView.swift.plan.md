# SettingsView.swift

## Responsibility

- Own local settings UI for theme mode, accent color, app version display, DeepSeek API key entry, and todo reminder mode controls.
- Persist the API key through `@AppStorage("openai_api_key")`.
- Own the user-facing local backup import/export entry points.
- Own the user-facing todo reminder mode, local notification permission, and system Reminders permission entry points.
- Show the read-only CloudKit sync preflight report.

## Boundaries

- Do not commit default API keys or populate the key from source-controlled configuration.
- Do not send network requests from this view; AI calls remain owned by `OpenAIService` and ViewModels.
- Do not implement backup parsing or SwiftData merge rules in the view; keep that logic in `BackupService`.
- Do not implement notification scheduling rules in the view; keep local eligibility in `TodoNotificationPlanner` and scheduling in the notification service.
- Do not implement system reminder lead-time rules or EventKit writes in the view; keep planning in `SystemReminderAgent` and writes in `SystemReminderService`.
- Do not trigger CloudKit network requests or enable sync from the preflight section.

## Behavior Notes

- The API key is stored only in local `UserDefaults`.
- The clear action removes the local key by assigning an empty string.
- The key input uses `SecureField` and shows only configured/unconfigured status, never the full key.
- The AI section uses explicit `Section { } header: { } footer: { }` syntax for Xcode 16.4 compatibility.
- The backup section exports `.easynotebackup` files and previews import counts before writing.
- Backup operations are consumed through `BackupServiceProviding`; the production default remains `BackupService`.
- Successful import posts `easyNoteBackupDidImport` so active ViewModels reload SwiftData-backed lists.
- Local todo reminder operations are consumed through async/throws `TodoNotificationSchedulingProviding`; enabling EasyNote notifications requests permission and reconciles current todos, while disabling them cancels EasyNote todo notifications without changing todo data.
- Reminder mode is persisted through `TodoReminderModeStore`; the legacy `todo_notifications_enabled` flag remains synchronized for PR #19 compatibility.
- System Reminders operations are consumed through `SystemReminderAgentProviding` and async/throws `SystemReminderWritingProviding`; Settings owns separate write and authorization-status tasks so foreground refreshes cannot cancel a partially completed sync.
- Switching to system Reminders mode disables EasyNote local notifications, cancels EasyNote-created local todo notifications, and syncs current todos immediately when Reminders access is already granted. If Settings is still waiting for the current Reminders authorization refresh, it performs the sync when the publisher reports writable access.
- Switching from system mode, or from off after system reminders may have been written, to EasyNote notifications reconciles local notifications and attempts to remove EasyNote-marked Apple Reminders for current todos so later local-mode edits do not leave stale system alerts. A first-time off-to-local switch does not attempt Reminders cleanup.
- Switching to off cancels EasyNote local notifications but does not bulk-delete Apple Reminders that were already written.
- Local notification authorization denial cancels EasyNote-created pending todo notification requests before persisting the mode back to off.
- If system notification permission becomes schedulable while the app-level reminder toggle is still enabled, Settings reconciles current todos so reminders are recreated without waiting for a todo edit.
- Reminder-mode errors remain visible even if Settings resets the selected mode after a denied permission request.
- Settings refreshes notification authorization status when the app returns to the foreground. A denied-to-full-access Reminders transition in system mode starts a write task for current todos, while later status refreshes do not cancel that write.
- Reconciliation messages report retained reminder slots, not just the raw eligible todo count.
- The CloudKit preflight section renders a supplied `CloudKitPreflightReport`; the production default is `CloudKitSyncPreflight.currentProjectReport()`.

## Tests

- Covered indirectly by app build and launch UI smoke.
- Add focused UI tests only after stable accessibility identifiers are introduced for Settings controls.
- `BackupService` unit tests cover the data contract and import/export behavior behind the Settings actions.
- `CloudKitSyncPreflight` unit tests cover the preflight report shown by Settings.
- Todo notification and system reminder unit tests cover planner/agent rules, mode-store migration, and ViewModel routing behind the Settings controls.
