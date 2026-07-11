# AppearanceSettingsSection.swift

## Responsibility

- Render dark-mode and accent-color controls backed by the shared `ThemeManager`.

## Boundaries

- Do not duplicate theme persistence or introduce independent local appearance state.
- Available accent names remain owned by the current product UI until a separate theme plan changes them.

## Behavior Notes

- Dark-mode toggles call `ThemeManager.toggleDarkMode()`.
- Accent selection calls `ThemeManager.setAccentColor(_:)` with the existing blue, green, purple, red, and orange values.

## Tests

- App build and manual Settings smoke cover SwiftUI binding behavior.
