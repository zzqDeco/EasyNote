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
- todo draft cancellation without SwiftData insertion, legacy/current recurrence parsing, persistence dismissal decisions, and idempotent keyboard observer registration
- `ChatSession.generateSummary`
- `ChatSession` and `SessionMessage` basic integrity
- V1 versioned-schema compatibility with the existing model layout
- persistence startup success/failure/retry, recovery copying of store/WAL/SHM, and visible rebuild failure through injected container/file seams
- explicit chat-session/message deletion and rollback after an injected save failure
- chat requests remain bound to their captured session across switching/deletion, and provider failure never produces fabricated diary claims
- `AIActionResult` success/failure state and input preview generation
- diary AI result application helpers that only mutate summary or transcription text after explicit confirmation
- existing-diary draft commit, rollback, mood normalization, transcription isolation, and recording ownership
- `SystemReminderAgent` lead-time and skip decisions for Apple Reminders proposals
- `TodoViewModel` routing to fake local notification schedulers or fake system reminder writers based on the active reminder mode
- reminder-service timeout, cancellation, late EventKit callback, duplicate marker, missing-list, system-error, and local notification add-error behavior through injected adapters
- successful Todo SwiftData persistence when a local notification or system Reminders side effect fails

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

- launch with an existing local store and confirm all existing diary, todo, and chat data remains available
- force or simulate store-open failure and confirm the app shows retry instead of terminating or creating a replacement store
- confirm the rebuild action requires destructive confirmation and creates a timestamped `Documents/EasyNoteRecovery` copy containing the store and any existing WAL/SHM sidecars before rebuilding
- force or simulate rebuild failure and confirm the recovery location remains visible and its files remain intact
- create a diary entry
- force a new-diary save or detail-delete failure and confirm the current screen, typed input, and retry path remain visible with the persistence error
- edit diary content, mood, and tags
- cancel an existing-diary edit after changing content, mood, and tags and confirm every persisted field remains unchanged
- replace an existing diary recording, save, and confirm the old recording is removed only after the new URL persists
- force or simulate an existing-diary save failure and confirm the editor remains open, the original recording remains usable, and the pending recording can be retried or discarded
- search diary title, content, and tags
- filter diaries by tag, mood, favorite state, and date range, then clear filters
- open diary review and confirm monthly overview, tag trends, mood distribution, and recent favorites render from the full diary set
- confirm diary review results do not change when the diary list has an active search or filter
- create and complete a todo
- open Explore or unified todo add, type a draft, cancel, and confirm no placeholder todo was created
- force a todo create, edit, or detail-delete failure and confirm the current screen and draft remain visible with the persistence error
- open recurring todos stored with both legacy `daily` and current `每天` values and confirm both display `每天重复`
- create a recurring todo and complete it once
- switch todo segments for today, overdue, upcoming, no-date, recurring, and completed groups
- create a todo from a recommendation and confirm it appears in the expected todo group
- enable todo reminders in Settings, grant notification permission, and confirm a future-deadline todo schedules without changing todo data
- complete or delete a reminded todo and confirm its pending reminder is canceled
- disable todo reminders in Settings and confirm pending EasyNote todo reminders are canceled without deleting todos
- switch Settings -> 提醒方式 to 系统提醒事项, grant Reminders permission, and create a future-deadline todo such as `明天 10 点提交报告`
- switch from EasyNote 通知 to 系统提醒事项 with existing future-deadline todos and confirm current todos are written to Apple Reminders
- confirm Apple Reminders contains one reminder with the todo title, matching due date, an earlier alarm chosen by the agent, and an `EasyNoteTodoID:<uuid>` marker in notes
- edit the todo deadline and confirm the existing marked system reminder updates instead of duplicating
- complete the todo and confirm the marked system reminder is completed
- delete an EasyNote todo and confirm only the matching EasyNote-marked system reminder is removed
- switch back to EasyNote 通知, including after an intermediate off state following prior System Reminders use, and confirm current EasyNote-marked Apple Reminders are removed and new todos no longer write system reminders
- on a fresh install with no prior System Reminders use, switch from off to EasyNote 通知 and confirm no unrelated Reminders cleanup permission error is shown
- configure and clear the DeepSeek API key in Settings
- open Settings and confirm the iCloud sync preflight section shows the current local-first state as not ready for real sync
- start AI actions with an empty key and confirm the failure is user-visible
- send a note-exploration request, switch or delete the originating session before completion, and confirm no response appears in another session
- simulate an unavailable AI provider and confirm only factual local diary results are shown; unmatched queries show a retry action instead of an invented answer
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

Local simulator execution requires the installed CoreSimulator service to match Xcode. Record the exact version/destination error when it does not; generic simulator compilation and generic-device builds remain useful source checks, while hosted CI should use its matched Xcode/runtime pairing.
