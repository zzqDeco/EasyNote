# Speech Diary Flow

## Summary

- Make speech transcription a reliable draft input flow instead of an implicit content overwrite path.
- Keep this slice local-first: no schema changes, no real-device CI dependency, and no broad audio architecture rewrite.

## Scope

- Publish speech and microphone permission states from `SpeechRecognitionService`.
- Route recording start/stop through `DiaryViewModel`; views should not configure `AVAudioSession` directly.
- Add a pure diary draft text helper for insert/replace behavior.
- Update `TranscriptionDisplayView` so applying transcription is an explicit insert or replace action supplied by the parent view.
- Preserve existing AI refinement/expand/summary behavior, but keep results in `transcribedText` until the user applies them.
- Update current-state docs and focused unit tests.

Non-goals:

- No CI test for real microphone, speech recognition, or permission prompts.
- No SwiftData schema change for storing full transcription history.
- No keychain, CloudKit, or audio file sync changes.

## Implementation

- Add `SpeechPermissionStatus` and `MicrophonePermissionStatus` enums and publish them from `SpeechRecognitionService`.
- `SpeechRecognitionService.startRecording()` refreshes permission state, lets first-run `.notDetermined` prompts complete without auto-starting recording from the permission callback, and fails with a user-visible error before touching the audio engine when permissions are denied or restricted.
- `DiaryViewModel` mirrors permission state, owns recording actions, captures pending recording output for unsaved draft entries, and saves audio/transcription to the current entry only when one exists.
- Add `DiaryTranscriptionApplyMode` and `DiaryDraftComposer` for pure insert/replace text composition.
- `CreateDiaryView`, `DiaryEditView`, and the still-compiled `NewDiaryView` use explicit `onApplyTranscription` closures instead of `NotificationCenter` content application.
- `TranscriptionDisplayView` displays recording, processing, finished, error, and permission failure states, and only exposes insert/replace actions after speech recognition is no longer recording or processing.
- `SpeechRecognitionService` writes audio buffers to a local file during recording so saved diary entries only receive existing recording URLs, and tears down the audio pipeline on file setup/write/start failures.
- New-entry views delete abandoned or superseded captured `.caf` files on cancel/dismiss or re-record, existing diary entries delete replaced recording files only after the new recording reference saves successfully, and diary deletion removes its saved local recording file after the model delete saves.

## Test Plan

- Unit tests cover inserting transcription into existing content.
- Unit tests cover replacing content with transcription.
- Unit tests cover empty transcription preserving existing draft content.
- Unit tests cover recording-state gating for transcription apply actions.
- Unit tests cover deleting a replaced local recording while preserving the replacement file and avoiding deletion when the replacement is the same file.
- Local checks: `git diff --check`, `xcodebuild -list -project EasyNote.xcodeproj`, docs link sanity, and secret scan.
- Full unit tests rely on GitHub CI if the local simulator runtime remains unavailable.
- Real recording and permission behavior remains a manual real-device or compatible-simulator smoke check.

## Assumptions

- A new diary draft can capture an audio URL before the entry exists and attach that URL at save time, including when the user taps Save while recording is still active.
- Insert mode appends transcription after a blank line when the draft already has content.
- Existing `transcribedText` remains the handoff surface for raw transcription and AI-refined text until a later ViewModel/DI cleanup.
