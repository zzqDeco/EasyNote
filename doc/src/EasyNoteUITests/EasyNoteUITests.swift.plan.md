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
- Launch performance remains template-level smoke coverage and should be tightened only after CI runtime is stable.

## Tests

- Not part of the first blocking GitHub Actions gate because hosted UI test runner startup is not stable yet.
- Run locally only when the installed simulator runtime matches the selected Xcode SDK.
