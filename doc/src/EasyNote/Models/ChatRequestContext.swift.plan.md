# ChatRequestContext

## Responsibility

- Represent the immutable session, conversation, and diary facts used by one exploration request.

## Boundaries

- Do not retain SwiftData model objects or read current UI selection after construction.
- Provider transport belongs to `ChatResponseGenerator`; persistence belongs to `ChatSessionViewModel`.

## Behavior Notes

- Retry preserves the captured facts and session ID while assigning a new request ID.
- Snapshot types are `Sendable` values so asynchronous work cannot observe later model mutations.

## Tests

- Cover retry identity, prompt snapshots, local matching, and session-bound completion behavior.
