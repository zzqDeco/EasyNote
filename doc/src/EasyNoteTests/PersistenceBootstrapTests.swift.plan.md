# PersistenceBootstrapTests.swift

## Responsibility

- Verify versioned-schema compatibility and persistence lifecycle state/recovery behavior without user data.

## Boundaries

- Use temporary directories and in-memory containers only.
- Do not depend on the app Documents directory or live CloudKit.

## Behavior Notes

- A separate plain-schema fixture freezes the legacy layout. Tests assert entity-name equality, create legacy data, adopt it with V1 without a plan, and then reopen it with `EasyNoteMigrationPlan` while retaining data.
- Tests also cover injected startup failure/retry, exact store/WAL/SHM recovery copies, and rebuild failure preservation.

## Tests

- Compile through generic simulator build-for-testing and execute on a compatible simulator runtime.
