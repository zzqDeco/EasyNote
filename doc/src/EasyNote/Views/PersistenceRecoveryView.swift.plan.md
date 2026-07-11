# PersistenceRecoveryView.swift

## Responsibility

- Render persistence loading, ready app content, and failed startup actions.
- Require explicit destructive confirmation before invoking recovery-copy-and-rebuild.

## Boundaries

- The view does not perform file operations or construct containers; those belong to `PersistenceBootstrap`.
- Do not present rebuild as automatic or equivalent to Settings JSON restore.

## Behavior Notes

- Ready state applies the shared container to `ContentView`.
- Failed state offers retry and, for persistent stores, a confirmed recovery rebuild.
- Rebuild failures display the preserved recovery-copy path.

## Tests

- Bootstrap unit tests cover actions and state transitions; app-entry UI smoke covers successful in-memory launch.
