# EasyNoteUITests.swift

## Responsibility

- Hold launch-level UI smoke coverage for the app target.
- Prove that the app can be installed, launched, and enter the foreground in a simulator test run.
- Exercise non-destructive navigation across the primary tabs using stable accessibility identifiers with label fallback.

## Boundaries

- Do not add brittle visual walkthroughs until primary flows have stable accessibility identifiers.
- Do not depend on local user data, network access, microphone permissions, or configured API keys.

## Behavior Notes

- `testLaunches` starts the app and asserts that it reaches the foreground.
- `testPrimaryTabNavigationSmoke` switches across explore, todo, diary, and settings without creating, editing, deleting, recording audio, calling the network, or requiring a configured API key.
- UI tests create apps through `XCUIApplication.easyNoteUITestApp()` so launch smoke, navigation smoke, screenshot launch tests, and launch performance all share `-easynote-ui-testing`, `-easynote-disable-animations`, and `EASYNOTE_UI_TESTING=1`.
- Launch performance remains template-level smoke coverage and should be tightened only after CI runtime is stable.

## Tests

- Not part of the first blocking GitHub Actions gate because hosted UI test runner startup is not stable enough for required PR checks.
- The manual `UI Smoke` workflow runs the launch and primary-tab navigation tests on GitHub-hosted macOS runners.
- Run locally only when the installed simulator runtime matches the selected Xcode SDK.
