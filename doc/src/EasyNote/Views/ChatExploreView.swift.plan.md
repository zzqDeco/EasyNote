# ChatExploreView

## Responsibility

- Render the selected chat session and construct immutable request snapshots from the selected session and loaded diaries.

## Boundaries

- Do not own provider tasks, write messages by `currentSession` after an await, or create fallback claims.
- Request lifecycle and persistence belong to `ChatSessionViewModel`.

## Behavior Notes

- Processing and retry UI are scoped to the selected session.
- Input is cleared only after the user message is saved and the request is accepted.

## Tests

- Cover session switching/deletion through ViewModel tests and retain the existing non-network UI navigation smoke.
