# EasyNote MVP Acceptance

This document describes what the current validation checks prove for the public, local-first EasyNote MVP.

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
- `AIActionResult` success/failure state and input preview generation
- diary AI result application helpers that only mutate summary or transcription text after explicit confirmation

When diary, todo, chat, or AI parsing behavior changes, add focused tests before relying on manual verification.

## UI Smoke Coverage

Current UI tests cover:

- app launch into the foreground through `EasyNoteUITests.testLaunches`
- non-destructive primary tab navigation through explore, todo, diary, and settings
- stable accessibility identifiers for primary tab buttons, diary search/filter/add controls, todo focus controls, and Settings API key controls
- UI-test launch isolation through an in-memory SwiftData store, reset local defaults, and disabled animations
- launch performance smoke from the generated UI test target

The first blocking CI gate runs unit tests only. Hosted UI smoke is available through the manual `UI Smoke` GitHub Actions workflow, but it is not yet a required PR check.

## Manual Smoke

Before treating a branch as a usable app build, manually verify:

- create a diary entry
- edit diary content, mood, and tags
- search diary title, content, and tags
- filter diaries by tag, mood, favorite state, and date range, then clear filters
- open diary review and confirm monthly overview, tag trends, mood distribution, and recent favorites render from the full diary set
- confirm diary review results do not change when the diary list has an active search or filter
- create and complete a todo
- create a recurring todo and complete it once
- switch todo segments for today, overdue, upcoming, no-date, recurring, and completed groups
- create a todo from a recommendation and confirm it appears in the expected todo group
- configure and clear the DeepSeek API key in Settings
- open Settings and confirm the iCloud sync preflight section shows the current local-first state as not ready for real sync
- start AI actions with an empty key and confirm the failure is user-visible
- generate a diary AI summary with a configured key and confirm the diary summary is unchanged until Apply is tapped
- generate a transcription refine, expand, or summary result and confirm transcription text is unchanged until Apply is tapped
- copy a pending AI result and confirm no diary or transcription field changes
- discard a pending AI result and confirm no diary or transcription field changes
- open recent AI results in diary, transcription, or explore flows and confirm successful and failed outcomes are reviewable in the current session
- record speech on a real device or compatible simulator, stop recording, confirm transcription appears before it is applied
- save a new diary while recording is active and confirm the entry keeps the captured audio URL
- cancel a new diary after stopping a recording and confirm the unsaved local recording is not retained by any diary entry
- delete a saved voice diary and confirm its local recording is not retained by any diary entry
- deny speech or microphone permission and confirm the editor shows a user-visible reason without losing typed content
- insert transcription into existing diary content and confirm it appends after the existing text
- replace diary content with transcription and confirm the replace is explicit
- export a backup from Settings and confirm the preview count includes diary, todo, chat, message, and recording totals
- import a backup after adding unrelated local data and confirm same-ID records update while unrelated local records remain
- import a backup containing a voice diary and confirm the restored diary points to a local `restored_recording_<uuid>` audio file
- try importing a malformed or unsupported backup file and confirm no local records are changed

## Known Local Limitation

The local machine previously had Xcode 26.5 SDKs without matching iOS 26.5 simulator runtimes. That blocks local `xcodebuild test` until the matching runtime is installed, but hosted CI should use the default Xcode/runtime pairing provided by `macos-15`.
