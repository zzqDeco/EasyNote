# SettingsView.swift

## Responsibility

- Own local settings UI for theme mode, accent color, app version display, and DeepSeek API key entry.
- Persist the API key through `@AppStorage("openai_api_key")`.

## Boundaries

- Do not commit default API keys or populate the key from source-controlled configuration.
- Do not send network requests from this view; AI calls remain owned by `OpenAIService` and ViewModels.

## Behavior Notes

- The API key is stored only in local `UserDefaults`.
- The clear action removes the local key by assigning an empty string.
- The AI section uses explicit `Section { } header: { } footer: { }` syntax for Xcode 16.4 compatibility.

## Tests

- Covered indirectly by app build and launch UI smoke.
- Add focused UI tests only after stable accessibility identifiers are introduced for Settings controls.
