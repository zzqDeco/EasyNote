# ChatResponseGenerator

## Responsibility

- Build provider prompts from `ChatRequestContext` and map provider completion into provider, local, failure, or cancelled outcomes.

## Boundaries

- Do not read `currentSession`, SwiftData, or live diary collections.
- Do not fabricate experiences, moods, correlations, or writing-style conclusions.

## Behavior Notes

- Missing keys fail before the provider call.
- Provider failure uses `LocalDiaryQueryAnalyzer`; no factual match produces a retryable failure rather than a persisted assistant message.

## Tests

- Cover provider success/empty/failure/cancellation, factual local results, unmatched failures, and prompt snapshot usage.
