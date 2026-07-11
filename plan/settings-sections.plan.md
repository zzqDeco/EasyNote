# Settings Sections Decomposition

## Summary

- Decompose the monolithic Settings screen into feature-owned SwiftUI sections without changing user-visible behavior.
- Introduce one dependency bundle so Settings composition has an explicit, testable boundary for its existing services and stores.

## Scope

- Split Settings into `AISettingsSection`, `BackupSettingsSection`, `ReminderSettingsSection`, `SyncSettingsSection`, and `AppearanceSettingsSection`.
- Reduce `SettingsView` to navigation/form composition plus forwarding of SwiftUI environment values.
- Add `SettingsDependencies` for the existing backup, notification, system reminder, reminder-mode, and CloudKit preflight dependencies.
- Preserve API-key and reminder defaults keys, file import/export and confirmation flow, permission/status refresh behavior, reminder transitions, CloudKit preflight rendering, appearance controls, copy, and accessibility identifiers.
- Update stable architecture and source ownership documentation for the new composition boundary.
- Do not change SwiftData models, backup formats, service protocols, reminder scheduling rules, CloudKit enablement, API-key storage, or privacy/Keychain behavior.

## Implementation

- Keep each section's existing state and callbacks with the section that renders them; service-level parsing, persistence, notification, EventKit, and preflight rules remain in their current owners.
- Have `SettingsView` read `ModelContext` and `ScenePhase`, then pass them with `SettingsDependencies` to the relevant sections.
- Keep production dependency defaults identical to the previous `SettingsView` initializer defaults while allowing tests and previews to supply replacements as one value.
- Keep backup document type registration and file presenter state with `BackupSettingsSection`.
- Keep reminder authorization publishers, foreground refresh, write-task cancellation, and legacy local-notification `@AppStorage` coordination with `ReminderSettingsSection`.

## Test Plan

- Add a focused unit test proving `SettingsDependencies` preserves explicitly injected services, stores, and reports.
- Run `git diff --check` and the repository Markdown relative-link check.
- Run `xcodebuild -list`, generic simulator `build-for-testing`, Release generic-device build, and focused unit tests when a simulator runtime is available.
- Run the repository secret scan and review the final diff for behavior or identifier drift.
- If simulator execution is unavailable, record the exact destination or CoreSimulator failure and retain compile-only results separately.

## Assumptions

- The current service protocols and production implementations remain the dependency contract for this slice.
- `UserDefaults` remains the API-key storage mechanism until the separate privacy/Keychain follow-up.
- The current read-only CloudKit preflight remains blocked/local-first and this refactor does not enable synchronization.
