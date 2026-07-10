# Chat Response Integrity

## Summary

- Bind every exploration request and persisted response to the session that originated it.
- Replace random provider-failure text with deterministic results derived only from captured diary facts.

## Scope

- Add immutable chat request, conversation, and diary snapshots.
- Move request task ownership, cancellation, retry, and explicit-session message writes into `ChatSessionViewModel`.
- Keep provider configuration, AI privacy consent, and persistent AI history changes outside this slice.

## Implementation

- Persist the user message before starting the provider request, then use the captured session UUID for every completion.
- Cancel or invalidate requests when their session is switched away from, cleared, or deleted.
- Store processing and failure state per session so independent requests cannot overwrite each other.
- Use `LocalDiaryQueryAnalyzer` only for titles, dates, previews, tags, moods, and counts present in the captured snapshots; unmatched failures remain retryable UI errors.

## Test Plan

- Cover explicit-session writes, switching/deletion cancellation, independent concurrent sessions, save failure, empty keys, and provider failures with and without matching facts.
- Run whitespace, documentation links, project listing, Debug/Release generic builds, and hosted unit tests.

## Assumptions

- Switching away from a session intentionally cancels its active request.
- Retry reuses the captured facts and conversation but receives a new request UUID and does not duplicate the user message.
