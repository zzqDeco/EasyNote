# ExploreViewModel.swift

## Responsibility

- Own recommendation UI state, cache loading, and existing recommendation-generation orchestration.

## Boundaries

- Keep published recommendation state and SwiftData reads on the main actor.
- Do not log diary source text or generated recommendation text.

## Behavior Notes

- Recent-entry filtering and sorting happens on main-actor-fetched values, avoiding non-sendable SwiftData key-path descriptors.
- Unified logs contain only static events and aggregate recommendation counts.

## Tests

- Existing recommendation tests run through the main-actor unit-test suite and injected AI fakes.
