# CloudKitSyncPreflight.swift

## Responsibility

- Own the pure readiness checklist for future real CloudKit sync enablement.
- Convert explicit project configuration into pass, warning, or blocked checks that can be tested without CloudKit network access.

## Boundaries

- Do not perform CloudKit network requests, read or write SwiftData, mutate entitlements, or enable sync.
- Do not replace `CloudKitService`; this helper only documents and evaluates prerequisites.

## Behavior Notes

- The current project report remains blocked because iCloud entitlements are absent, Debug simulation is enabled, schema deployment is not verified, record identity round-trip is not implemented, and manual real-device validation is not complete.
- SwiftData automatic CloudKit sync is treated as a separate migration choice; the current service-managed boundary expects `EasyNoteApp` to keep `cloudKitDatabase: .none`.
- The documented future conflict strategy is stable CloudKit record identity plus `DiaryEntry.lastModified` precedence.

## Tests

- `EasyNoteTests` covers the current blocked report, a fully ready service-managed report, and mismatched container blocking.
