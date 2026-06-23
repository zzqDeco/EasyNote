# ServiceProtocols.swift

## Responsibility

- Define narrow service-facing protocols for AI, speech recognition, CloudKit diary sync, local backup behavior, and todo notification scheduling.
- Provide protocol extension defaults only where they preserve existing concrete service call ergonomics.

## Boundaries

- Do not add business rules, provider parsing, persistence merge logic, or audio engine behavior here.
- Do not turn these protocols into a broad dependency-injection framework.
- Keep protocol methods limited to behavior consumed across module boundaries.

## Behavior Notes

- AI and speech state is exposed as erased `AnyPublisher` streams so ViewModels do not rely on concrete `@Published` storage.
- Production initializers still default to concrete services; protocol injection exists for tests and future narrow refactors.
- Backup export keeps a protocol-extension default for `exportedAt` so callers can keep using the current production path.
- Todo notification scheduling is exposed through synchronize/cancel/reconcile operations so `TodoViewModel` does not import `UserNotifications`.

## Tests

- Unit tests should use fake services through these protocols when asserting ViewModel behavior that previously required concrete network, device, cloud, file, or notification services.
- `xcodebuild -list` and CI unit tests should catch protocol signature drift that breaks production service conformance.
