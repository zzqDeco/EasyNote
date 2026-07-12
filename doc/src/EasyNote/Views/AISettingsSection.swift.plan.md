# AISettingsSection.swift

## Responsibility

- Own transient DeepSeek API-key entry, explicit Keychain save/clear actions, migration feedback, and configured status.
- Present the first-use content disclosure plus explicit grant and revoke controls.

## Boundaries

- Do not contain a default key, display the stored key, or send provider requests.
- Delegate credential and consent persistence through injected protocols.

## Behavior Notes

- The field remains a transient `SecureField` and never renders the stored value.
- Save, clear, migration, and read-back failures are visible in the section.
- Saving or migrating a key never grants consent; configured but denied state presents the disclosure before first use.
- Existing accessibility identifiers remain, with stable save/grant/revoke identifiers added.

## Tests

- `AIPrivacyTests` covers the injected storage and consent behavior behind the section.
- UI smoke coverage uses the stable accessibility identifiers and verifies the disclosure manually.
- Secret scanning must continue to reject source-controlled credentials.
