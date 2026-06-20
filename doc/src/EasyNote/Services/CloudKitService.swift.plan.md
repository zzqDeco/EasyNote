# CloudKitService.swift

## Responsibility

- Own CloudKit account checks, audio file storage, diary sync, user ID, and quota helper behavior.
- Provide a Debug simulation mode that keeps local prototype usage working without a paid/ready iCloud setup.

## Boundaries

- Do not enable real iCloud sync until `CloudKitSyncPreflight` reports no blocking checks for the target enablement branch.
- Do not put UI presentation decisions in this service; expose status and errors for views/ViewModels.

## Behavior Notes

- Debug builds currently set `isSimulationMode = true`.
- The current placeholder container ID is `iCloud.io.github.zzqDeco.EasyNote`, sourced from `CloudKitSyncPreflight.defaultContainerIdentifier`.
- Sync status is published and mirrored through `NotificationCenter`.
- Real sync remains blocked while iCloud entitlements, schema deployment, record identity round-trip, and manual validation are incomplete.

## Tests

- Local CI does not prove real CloudKit behavior.
- `CloudKitSyncPreflight` unit tests cover the readiness checklist, but real sync still requires manual or integration validation in a future CloudKit enablement plan.
