# ChatSessionViewModel.swift

## Responsibility

- Own persisted chat-session UI state, session-bound request tasks, cancellation, retries, and message persistence.

## Boundaries

- Keep published state and the SwiftData UI context on the main actor.
- Do not log chat prompts, responses, related entry identifiers, or credentials.

## Behavior Notes

- Provider work crosses the task boundary through `ChatResponseProviderTransport`; completion is validated against the captured request/session before persistence.
- SwiftData fetch results are sorted on the main actor rather than sending key-path descriptors through strict-concurrency checking.
- A save failure rolls back and discards the current UI `ModelContext`; sessions are refetched from the same container and current selection is restored by UUID. Rolled-back model or relationship objects are never restored into published state.
- Context recovery does not create a default session or cancel unrelated pending provider work. Request completion remains keyed by captured UUID values and persists through the replacement context.

## Tests

- `ChatResponseIntegrityTests` covers session capture, cancellation, retry, deletion, context rebuilding after failed message/title/clear/create saves, and concurrent session requests.
