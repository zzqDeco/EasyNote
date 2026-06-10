# EasyNote MVP Acceptance

This document describes what the current validation checks prove for the private EasyNote prototype.

## Local Checks

```bash
git diff --check
xcodebuild -list -project EasyNote.xcodeproj
xcodebuild -showdestinations -project EasyNote.xcodeproj -scheme EasyNote
xcodebuild test -project EasyNote.xcodeproj -scheme EasyNote -destination 'platform=iOS Simulator,name=<available simulator>'
```

`xcodebuild test` requires an installed simulator runtime compatible with the selected Xcode. If SDK and runtime versions do not match, record the exact destination/runtime error instead of reporting tests as passing.

## CI Checks

GitHub Actions runs the minimum CI contract on `macos-15`:

- checkout
- show toolchain versions
- whitespace check for the committed range
- `xcodebuild -list`
- simulator discovery
- `xcodebuild test -only-testing:EasyNoteTests`

The CI workflow is intentionally small. It does not package, sign, archive, publish releases, or enable CloudKit.

## Unit-Test Coverage

Current focused tests cover:

- `TodoItem.RecurringInterval.nextDate`
- `ChatSession.generateSummary`
- `ChatSession` and `SessionMessage` basic integrity

When diary, todo, chat, or AI parsing behavior changes, add focused tests before relying on manual verification.

## UI Smoke Coverage

Current UI tests cover:

- app launch into the foreground through `EasyNoteUITests.testLaunches`
- launch performance smoke from the generated UI test target

The first blocking CI gate runs unit tests only. Hosted UI test execution is not yet stable enough for the minimum gate; the launch smoke stays in the repository for local/manual verification and a future UI CI plan.

## Manual Smoke

Before treating a branch as a usable app build, manually verify:

- create a diary entry
- edit diary content, mood, and tags
- create and complete a todo
- create a recurring todo and complete it once
- configure and clear the DeepSeek API key in Settings
- start AI actions with an empty key and confirm the failure is user-visible
- record or simulate speech transcription permissions on a real device or compatible simulator

## Known Local Limitation

The local machine previously had Xcode 26.5 SDKs without matching iOS 26.5 simulator runtimes. That blocks local `xcodebuild test` until the matching runtime is installed, but hosted CI should use the default Xcode/runtime pairing provided by `macos-15`.
