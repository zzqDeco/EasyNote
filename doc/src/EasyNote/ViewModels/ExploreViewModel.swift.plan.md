# ExploreViewModel.swift

## Responsibility

- Own recommendation UI state, cache loading, and existing recommendation-generation orchestration.

## Boundaries

- Keep published recommendation state and SwiftData reads on the main actor.
- Do not log diary source text or generated recommendation text.

## Behavior Notes

- Recent-entry filtering stays in the SwiftData fetch descriptor so only the requested seven-day window is materialized; the bounded result is sorted on the main actor.
- A concrete `KeyPath<DiaryEntry, Date>` compatibility conformance covers the Xcode 26 Swift 5 strict-concurrency gap without making SwiftData model instances Sendable.
- Unified logs contain only static events and aggregate recommendation counts.

## Tests

- Existing recommendation tests run through the main-actor unit-test suite and injected AI fakes.
