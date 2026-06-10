# Branching And Workflow

EasyNote follows the same lightweight branch model used by the user's active projects.

## Branch Roles

- `main`: stable branch. Keep it releasable and avoid routine direct pushes.
- `dev`: integration branch. Routine implementation and docs work should land here first.
- `feature/*`: user-visible features.
- `fix/*`: bug fixes.
- `docs/*`: documentation-only work.
- `refactor/*`: internal structure changes without product behavior changes.
- `test/*`: test coverage and verification harness changes.
- `chore/*`: repository maintenance.
- `release/*`: release stabilization branches.

## Standard Flow

1. Start from a clean `dev`.
2. Create a topic branch from `dev`.
3. Keep the branch PR-sized and focused.
4. Update `plan/` before non-trivial implementation.
5. Update `doc/` and `README.md` when stable behavior or setup changes.
6. Open PR into `dev`.
7. Merge `dev` into `main` only after integration validation is clean.

## Validation Expectations

- Always run `git diff --check` for documentation-only changes.
- Run `xcodebuild -list -project EasyNote.xcodeproj` after project configuration changes.
- Run `xcodebuild test` against an installed simulator runtime when Swift code changes.
- If the installed Xcode SDK and simulator runtimes do not match, record the exact destination/runtime error and do not report tests as passing.

## Current Bootstrap State

- `main` contains the first consolidated private prototype.
- `dev` is the integration branch for upcoming EasyNote work.
- GitHub default branch remains `main`; local development should normally happen on `dev` or topic branches from `dev`.
