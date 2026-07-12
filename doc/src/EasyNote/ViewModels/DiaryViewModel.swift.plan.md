# DiaryViewModel.swift

## Responsibility

- Own diary UI state, SwiftData mutations, speech draft integration, and existing AI/cloud orchestration behavior.

## Boundaries

- Keep published state and the SwiftData UI context on the main actor.
- Do not move audio-engine work into this ViewModel or record diary content/paths in diagnostics.

## Behavior Notes

- Speech publishers feed main-actor-owned state, and permission completions update recording state only on that actor.
- Fetch results are sorted on the actor without passing SwiftData key paths across concurrency boundaries.
- Fallback lookup for an entry not already loaded scans SwiftData in fixed 128-entry batches, keeping memory bounded without sending predicate key paths across actors.
- Categorized logs use static lifecycle/failure events only.

## Tests

- Main-actor unit tests use injected speech/AI/cloud fakes and retain existing draft, persistence, and AI-result coverage.
