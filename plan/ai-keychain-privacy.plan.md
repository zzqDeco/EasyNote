# AI Keychain And Privacy Consent

## Summary

- Move the DeepSeek API key from plaintext `UserDefaults` storage into the iOS Keychain.
- Require explicit, revocable consent before any diary or transcription text can be sent to DeepSeek.

## Scope

- Add injectable credential, Security item, consent, and AI HTTP client boundaries.
- Migrate the legacy `openai_api_key` value only after a verified Keychain write, leaving the legacy value intact on failure.
- Replace direct Settings `@AppStorage` key editing with explicit Keychain save, clear, migration, and error feedback.
- Add a first-use consent disclosure and revoke action in AI Settings.
- Enforce key and consent checks in `OpenAIService` before creating a network publisher.
- Add focused unit coverage and synchronize README, architecture, interface, and source-note documentation.
- Do not change SwiftData models, backup behavior, CloudKit behavior, speech capture, or concurrency-only request coordination.

## Implementation

- `CredentialStoreProviding` exposes throwing API-key read, save, delete, and legacy migration operations.
- `KeychainCredentialStore` stores a generic-password item under service `io.github.zzqDeco.EasyNote`, account `deepseek_api_key`, and accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` through an injectable Security adapter.
- Migration treats an existing Keychain credential as authoritative, performs a Keychain write and matching read-back, and removes `UserDefaults["openai_api_key"]` only after verification succeeds. Repeated migration after success is a no-op.
- `AIContentConsentProviding` persists a separate boolean decision that defaults to denied. Saving or migrating a key never grants consent; revocation immediately returns the network boundary to fail-closed behavior.
- `AISettingsSection` keeps typed input transient, never re-renders the stored secret, and presents explicit save, clear, grant, and revoke actions with user-visible errors.
- The consent disclosure states that selected diary or transcription text is sent to DeepSeek, audio files are not sent, and the API key is used only as the authorization credential rather than prompt content.
- `OpenAIService` reads credentials through the store, checks consent, and only then delegates to its injected HTTP client.

## Test Plan

- Verify Keychain create, read, update, and delete behavior through an in-memory Security adapter, including required service, account, and accessibility attributes.
- Verify migration success, repeated no-op behavior, and preservation of the legacy value when write or read-back verification fails.
- Verify consent defaults to denied and supports grant and revoke.
- Verify unconsented and empty-key requests never reach the injected HTTP client.
- Run `git diff --check`, Markdown relative-link validation, current-tree and Git-history secret scans, `xcodebuild -list`, generic simulator `build-for-testing`, and Release generic-device build.
- Run local simulator tests only when `xcodebuild -showdestinations` reports a concrete available simulator; otherwise record the toolchain/runtime blocker.

## Assumptions

- Consent is app-wide for DeepSeek text processing and is stored separately from the credential.
- The API key must be transmitted to DeepSeek in the HTTP Authorization header, but it is never included in the diary/transcription prompt body.
- Real audio upload, provider switching, biometric Keychain access control, and SwiftData schema changes are outside this slice.
