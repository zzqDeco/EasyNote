# CredentialStore.swift

## Responsibility

- Define the throwing `CredentialStoreProviding` API-key boundary.
- Implement Security.framework generic-password CRUD and verified legacy migration.
- Translate Keychain `OSStatus` failures into user-readable credential errors.

## Boundaries

- Do not grant or infer AI content consent.
- Restore the prior Keychain item, or remove a newly created item, before reporting migration verification failure.
- Do not expose stored credential text to views for display.
- Do not include credentials in backups, SwiftData, logs, or provider prompt bodies.

## Behavior Notes

- The production item uses service `io.github.zzqDeco.EasyNote`, account `deepseek_api_key`, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Duplicate adds update the data for the same service/account item; missing-item deletes are idempotent.
- Legacy `UserDefaults["openai_api_key"]` is removed only after the authoritative value is written and exactly read back. Any write, read, or verification failure retains the legacy value.

## Tests

- `AIPrivacyTests` covers required attributes, CRUD, idempotent migration, write failure, and read-back mismatch.
- Current-tree and history secret scans must remain clean.
