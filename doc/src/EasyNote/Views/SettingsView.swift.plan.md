# SettingsView.swift

## Responsibility

- Compose the Settings form, navigation title, app version row, and bottom layout spacer.
- Read `ModelContext` and `ScenePhase` from SwiftUI and forward them to feature-owned sections.
- Forward the shared `ThemeManager` and `SettingsDependencies`, including AI credential/consent stores, without implementing feature behavior.

## Boundaries

- Do not own API-key, AI consent, backup presenter, reminder authorization/task, appearance-control, or preflight-rendering state.
- Do not resolve concrete services in `body`; production defaults and test replacements belong in `SettingsDependencies`.
- Do not move persistence, notification, EventKit, backup-format, or CloudKit rules into the composition shell.

## Behavior Notes

- Section order remains appearance, AI, reminders, backup, CloudKit preflight, about, and bottom spacing.
- Environment forwarding keeps SwiftData backup/reminder reads and foreground authorization refreshes tied to the same Settings presentation.
- `SettingsDependencies()` preserves the previous concrete production defaults.

## Tests

- Unit tests verify dependency-bundle injection and the existing service/planner behavior behind each section.
- UI smoke coverage relies on the unchanged Settings accessibility identifiers.
- App builds catch composition and SwiftUI environment wiring regressions.
