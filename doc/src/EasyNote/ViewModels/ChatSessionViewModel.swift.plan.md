# ChatSessionViewModel.swift

## Responsibility

- Own persisted chat-session UI state, session-bound request tasks, cancellation, retries, and message persistence.

## Boundaries

- Keep published state and the SwiftData UI context on the main actor.
- Do not log chat prompts, responses, related entry identifiers, or credentials.

## Behavior Notes

- Provider work crosses the task boundary through `ChatResponseProviderTransport`; completion is validated against the captured request/session before persistence.
- SwiftData fetch results are sorted on the main actor rather than sending key-path descriptors through strict-concurrency checking.

## Tests

- `ChatResponseIntegrityTests` covers session capture, cancellation, retry, deletion, persistence failure, and concurrent session requests.
