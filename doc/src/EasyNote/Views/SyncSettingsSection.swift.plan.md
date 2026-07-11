# SyncSettingsSection.swift

## Responsibility

- Render a supplied `CloudKitPreflightReport` as read-only overall status and detailed checks.

## Boundaries

- Do not run CloudKit requests, mutate SwiftData configuration, enable entitlements, or recalculate preflight policy.
- Readiness rules remain owned by `CloudKitSyncPreflight`.

## Behavior Notes

- Passed, warning, and blocked severities retain their existing text, symbols, and colors.
- Non-passing checks continue to show remediation text and the current container identifier.

## Tests

- `CloudKitSyncPreflight` unit tests cover report severity and contents.
- App build covers SwiftUI rendering against the supplied report contract.
