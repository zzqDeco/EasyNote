# SettingsView.swift

## Responsibility

- Own local settings UI for theme mode, accent color, app version display, and DeepSeek API key entry.
- Persist the API key through `@AppStorage("openai_api_key")`.
- Own the user-facing local backup import/export entry points.

## Boundaries

- Do not commit default API keys or populate the key from source-controlled configuration.
- Do not send network requests from this view; AI calls remain owned by `OpenAIService` and ViewModels.
- Do not implement backup parsing or SwiftData merge rules in the view; keep that logic in `BackupService`.

## Behavior Notes

- The API key is stored only in local `UserDefaults`.
- The clear action removes the local key by assigning an empty string.
- The key input uses `SecureField` and shows only configured/unconfigured status, never the full key.
- The AI section uses explicit `Section { } header: { } footer: { }` syntax for Xcode 16.4 compatibility.
- The backup section exports `.easynotebackup` files and previews import counts before writing.
- Backup operations are consumed through `BackupServiceProviding`; the production default remains `BackupService`.
- Successful import posts `easyNoteBackupDidImport` so active ViewModels reload SwiftData-backed lists.

## Tests

- Covered indirectly by app build and launch UI smoke.
- Add focused UI tests only after stable accessibility identifiers are introduced for Settings controls.
- `BackupService` unit tests cover the data contract and import/export behavior behind the Settings actions.
