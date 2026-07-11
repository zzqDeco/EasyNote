# PersistenceBootstrapTests.swift

## Responsibility

- Verify versioned-schema compatibility and persistence lifecycle state/recovery behavior without user data.

## Boundaries

- Use temporary directories and in-memory containers only.
- Do not depend on the app Documents directory or live CloudKit.

## Behavior Notes

- Tests cover pre-versioned store open, injected startup failure/retry, exact store/WAL/SHM recovery copies, and rebuild failure preservation.

## Tests

- Compile through generic simulator build-for-testing and execute on a compatible simulator runtime.
