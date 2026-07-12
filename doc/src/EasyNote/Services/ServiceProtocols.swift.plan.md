# ServiceProtocols.swift

## Responsibility

- Define narrow service-facing protocols for AI, speech recognition, CloudKit diary sync, local backup behavior, todo notification scheduling, and system Reminders writing.
- Provide protocol extension defaults only where they preserve existing concrete service call ergonomics.

## Boundaries

- Do not add business rules, provider parsing, persistence merge logic, or audio engine behavior here.
- Do not turn these protocols into a broad dependency-injection framework.
- Keep protocol methods limited to behavior consumed across module boundaries.

## Behavior Notes

- AI and speech state is exposed as erased `AnyPublisher` streams so ViewModels do not rely on concrete `@Published` storage.
- Production initializers still default to concrete services; protocol injection exists for tests and future narrow refactors.
- Backup export/import and JSON/file operations are async; the protocol-extension default for `exportedAt` preserves call-site ergonomics, and only methods receiving `ModelContext` are `MainActor` isolated.
- Todo notification scheduling is exposed through async/throws synchronize/cancel/reconcile operations so `TodoViewModel` does not import `UserNotifications` and can surface scheduling errors after a successful save.
- System Reminders writing is exposed through async/throws proposal apply, complete, remove, authorization refresh, and permission request operations so `TodoViewModel` and Settings do not import EventKit or own callback lifetimes.

## Tests

- Unit tests should use fake services through these protocols when asserting ViewModel behavior that previously required concrete network, device, cloud, file, notification, or EventKit services.
- `xcodebuild -list` and CI unit tests should catch protocol signature drift that breaks production service conformance.
