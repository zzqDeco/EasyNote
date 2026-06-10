# Basic CI Plan

Status: Delivered

## Delivered Behavior

- Added `.github/workflows/ci.yml` as the minimum hosted CI gate for EasyNote.
- CI runs on pushes to `main`, `dev`, and topic branches, and on PRs into `main` or `dev`.
- CI shows the hosted default Xcode toolchain, lists the project, dynamically chooses an iPhone simulator, and runs `xcodebuild test -only-testing:EasyNoteTests`.
- Tightened the launch UI smoke test so it is a concrete foreground launch assertion, but kept it outside the first blocking CI gate after hosted UI runner bootstrap proved unstable.

## Verification

- `git diff --check`
- local workflow YAML parse with Ruby
- `xcodebuild -list -project EasyNote.xcodeproj`
- CI run after pushing is the hosted-runtime validation source.

## Docs Absorbed By

- [MVP Acceptance](../doc/mvp-acceptance.plan.md)
- [Interfaces](../doc/interfaces.plan.md)
- [GitHub CI Workflow Source Note](../doc/src/.github/workflows/ci.yml.plan.md)
- [UI Tests Source Note](../doc/src/EasyNoteUITests/EasyNoteUITests.swift.plan.md)

## Retirement Criteria

- Retire this record once CI behavior has been stable and future CI changes are tracked in newer plans.
