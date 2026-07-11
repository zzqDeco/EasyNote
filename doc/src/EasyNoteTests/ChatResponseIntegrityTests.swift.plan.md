# ChatResponseIntegrityTests.swift

## Responsibility

- Verify session-bound chat request persistence, cancellation, retry, and deletion behavior with in-memory SwiftData contexts.

## Boundaries

- Use injected providers and save actions; do not contact DeepSeek or user stores.
- Keep persistence assertions focused on chat sessions and messages.

## Behavior Notes

- Session deletion tests assert that a successful delete leaves no related `SessionMessage` rows.
- Injected save failure tests assert `ModelContext.rollback()` retains both the session and every message without canceling an in-flight request.

## Tests

- Compile through generic simulator build-for-testing and execute on a compatible simulator runtime.
