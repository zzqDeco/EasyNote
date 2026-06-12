# UI Smoke And Accessibility

## Summary

- Add stable accessibility identifiers for the primary tab, diary, todo, and settings entry points.
- Extend UI smoke coverage with a non-destructive navigation test that does not depend on local data, network access, microphone permission, or an API key.
- Keep hosted GitHub CI focused on unit tests; UI tests remain local/manual until runner stability is proven.

## Scope

- Update SwiftUI views that expose core navigation and setup controls:
  - `EasyNote/Views/ContentView.swift`
  - `EasyNote/Views/DiaryListView.swift`
  - `EasyNote/Views/ExploreView.swift`
  - `EasyNote/Views/SettingsView.swift`
- Update `EasyNoteUITests/EasyNoteUITests.swift` with launch and tab navigation smoke coverage.
- Update current-state docs for UI smoke coverage and source ownership notes.

Non-goals:

- Do not add destructive create/edit/delete UI automation.
- Do not require UI tests in GitHub CI.
- Do not add dependencies on existing SwiftData records, microphone permission, DeepSeek keys, or network responses.

## Implementation

- Add stable identifiers for:
  - tabs: explore, todo, diary, settings
  - todo add button and todo segmented control
  - diary add button, search field, filter button, and clear filters button
  - Settings API key field and clear key button
- Keep identifiers implementation-local string literals for now; centralize only if UI automation grows enough to justify a shared contract file.
- Add a UI smoke test that launches the app, switches between the four tabs, and verifies the expected non-destructive control for each tab.
- Preserve the existing launch performance smoke.

## Test Plan

- `git diff --check`
- `xcodebuild -list -project EasyNote.xcodeproj`
- Local simulator available:
  - `xcodebuild test -project EasyNote.xcodeproj -scheme EasyNote -destination 'platform=iOS Simulator,name=<available simulator>' -only-testing:EasyNoteUITests`
- Hosted CI remains:
  - `xcodebuild test -project EasyNote.xcodeproj -scheme EasyNote -only-testing:EasyNoteTests`

## Assumptions

- SwiftUI tab item identifiers can be used by XCUITest on supported runtimes; the UI test keeps label-based fallback to avoid making the smoke brittle.
- Hosted UI tests are intentionally deferred until macOS runner behavior is stable for the app target.
