# UI CI Stabilization

## Summary

- Make UI smoke tests safer to run repeatedly by adding launch-time test isolation and a manual hosted workflow.
- Keep the default blocking CI gate focused on unit tests until UI runner stability is proven over repeated runs.

## Scope

- Add UI-test launch arguments and app-side test-mode isolation.
- Run UI tests against an in-memory SwiftData store and reset UI-test defaults for API key, theme, and recommendation cache.
- Add a manual GitHub Actions workflow for launch and primary-tab UI smoke tests.
- Update current-state acceptance and source notes.

Non-goals:

- Do not make UI tests blocking on every PR.
- Do not add destructive create/edit/delete UI automation.
- Do not depend on network, microphone permissions, local user data, or configured API keys.

## Implementation

- `EasyNoteUITests` launches the app through a shared `XCUIApplication.easyNoteUITestApp()` helper with `-easynote-ui-testing` and `-easynote-disable-animations`, including launch performance and screenshot launch coverage.
- `EasyNoteApp` uses an in-memory SwiftData configuration in UI-test mode and clears only UI-test local defaults.
- `.github/workflows/ui-smoke.yml` is `workflow_dispatch` only, selects the newest available deployment-compatible iPhone simulator, and runs `testLaunches` plus `testPrimaryTabNavigationSmoke`.
- The existing `CI` workflow remains unchanged as the required unit-test gate.

## Test Plan

- `git diff --check`
- YAML syntax check for GitHub workflows.
- `xcodebuild -list -project EasyNote.xcodeproj`
- Local UI test only when a compatible named simulator exists.
- GitHub PR CI continues to run `EasyNoteTests`; manual `UI Smoke` workflow can be dispatched for hosted UI validation.

## Assumptions

- UI-test launch isolation is acceptable because it only activates under explicit test arguments or `EASYNOTE_UI_TESTING=1`.
- The first stable hosted UI path should be manual before becoming required on PRs.
