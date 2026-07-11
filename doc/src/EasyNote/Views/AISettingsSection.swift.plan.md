# AISettingsSection.swift

## Responsibility

- Own DeepSeek API-key entry, configured status, and the destructive clear action.
- Persist `openai_api_key` through the existing `@AppStorage` path.

## Boundaries

- Do not contain a default key, move key storage to a different mechanism, or send provider requests.
- Keychain/privacy migration belongs to a separate planned change.

## Behavior Notes

- The field remains a `SecureField` and never renders the full stored value as status text.
- Empty or whitespace-only input displays unconfigured status; the clear action assigns an empty string.
- Accessibility identifiers remain `settings.apiKeyField` and `settings.clearApiKeyButton`.

## Tests

- UI smoke coverage uses the stable accessibility identifiers.
- Secret scanning must continue to reject source-controlled credentials.
