# CloudKit Sync Preflight

## Delivered Status

- Delivered to `dev` in PR #17 and promoted as part of the maintainability and sync-preflight promotion.
- Current-state CloudKit behavior remains owned by `doc/architecture.plan.md`, `doc/interfaces.plan.md`, `doc/mvp-acceptance.plan.md`, and the source notes under `doc/src/`.

## Summary

- Engineer the prerequisites for future CloudKit sync without enabling real iCloud synchronization in this slice.
- Make the current local-first state explicit in code, Settings UI, documentation, and tests so the next enablement PR has a concrete checklist instead of implicit assumptions.

## Scope

- Add a pure `CloudKitSyncPreflight` helper that evaluates container ID, entitlements, Debug simulation, SwiftData sync boundary, schema deployment, conflict strategy, record identity, and manual validation readiness.
- Show the current preflight report in Settings as read-only status.
- Update CloudKit architecture/interface docs, source notes, and MVP acceptance.
- Add focused unit tests for current blocked state, ready state, and mismatched container behavior.

Non-goals:

- Do not enable CloudKit entitlements.
- Do not turn on SwiftData automatic CloudKit sync.
- Do not deploy CloudKit schema or run live CloudKit tests in CI.
- Do not change SwiftData models, migrations, or local backup behavior.

## Implementation

- `CloudKitSyncPreflight.Configuration.currentProject` reflects the current repository state:
  - container ID is `iCloud.io.github.zzqDeco.EasyNote`
  - iCloud/CloudKit entitlements are absent
  - Debug simulation remains enabled
  - SwiftData automatic CloudKit sync remains disabled
  - CloudKit schema deployment and real-device validation are not complete
- `SettingsView` receives a preflight report with a production default and renders it as read-only status.
- The conflict strategy is documented as stable record identity plus `lastModified`-based conflict handling, but real sync remains blocked until record identity round-trip and manual validation are implemented.

## Test Plan

- Unit tests:
  - current local-first configuration is blocked and reports the expected blockers
  - a fully ready service-managed configuration passes
  - mismatched container IDs block sync readiness
- Local checks:
  - `git diff --check`
  - `xcodebuild -list -project EasyNote.xcodeproj`
  - Markdown relative link check
  - secret scan
- GitHub CI remains the source of truth for hosted `EasyNoteTests`.

## Assumptions

- The next real sync PR should use `CloudKitService` as the sync boundary unless a separate migration plan chooses SwiftData automatic CloudKit sync.
- Manual CloudKit validation results belong in the PR body/comment for the enablement PR, not a new permanent release-readiness document.
