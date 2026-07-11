# SettingsDependencies.swift

## Responsibility

- Bundle the existing Settings service protocols, reminder-mode store, and CloudKit preflight report for composition and tests.
- Preserve the previous concrete production defaults in one initializer.

## Boundaries

- Do not create new service behavior, persistence, global state, or lifecycle coordination.
- Keep API-key and theme storage with their existing owners; do not add Keychain behavior in this boundary.

## Behavior Notes

- Default backup, notification, reminder, mode-store, and preflight values match the former `SettingsView` initializer defaults.
- Explicitly injected reference dependencies retain their identity so one section does not silently replace a test or preview double.

## Tests

- Unit tests verify explicit scheduler, writer, mode-store, and report injection.
- App builds verify the concrete production defaults satisfy their protocols.
