# CloudKitService.swift

## Responsibility

- Own CloudKit account checks, audio file storage, diary sync, user ID, and quota helper behavior.
- Provide a Debug simulation mode that keeps local prototype usage working without a paid/ready iCloud setup.

## Boundaries

- Do not enable real iCloud sync without a dedicated plan covering entitlements, container ID, schema, conflict handling, and validation.
- Do not put UI presentation decisions in this service; expose status and errors for views/ViewModels.

## Behavior Notes

- Debug builds currently set `isSimulationMode = true`.
- The current placeholder container ID is `iCloud.io.github.zzqDeco.EasyNote`.
- Sync status is published and mirrored through `NotificationCenter`.

## Tests

- Local CI does not prove real CloudKit behavior.
- Real sync requires manual or integration validation in a future CloudKit enablement plan.
