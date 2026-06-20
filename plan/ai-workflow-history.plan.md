# AI Workflow History

## Summary

- Add a session-level AI result history so diary and transcription AI outputs can be reviewed, applied, copied, or discarded before mutating diary content.
- Keep the slice local-first and non-persistent: no SwiftData schema change, no provider changes, and no DeepSeek request-shape changes.

## Scope

- Add a pure `AIActionResult` model for current ViewModel lifetime history.
- Update `DiaryViewModel` AI actions to record success and failure results instead of immediately applying generated text to diary fields or transcription text.
- Add explicit apply/copy/discard UI for pending AI results in diary summary and transcription flows.
- Update docs under `doc/` and source notes for AI result confirmation behavior.

Non-goals:

- Do not persist AI history across app launches.
- Do not add new AI providers, settings, or key storage.
- Do not change DeepSeek endpoint, model, temperature, max token values, or parser fallback behavior.
- Do not add real network tests.

## Implementation

- Introduce `AIActionResult` as an app-local Codable/Equatable/Identifiable value with action type, input preview, output text, timestamp, success flag, and optional failure message.
- Keep `DiaryViewModel.aiActionHistory` and `DiaryViewModel.pendingAIResults` as `@Published` current-session state.
- Track pending diary and transcription results per application target/source scope, and bind diary summary results to the source `DiaryEntry.id` so navigation cannot apply a summary to the wrong diary.
- Store a deterministic input fingerprint with text-generating results and reject Apply when diary or transcription source text has changed.
- Record whether transcription AI input came from the transcription buffer or an editor-content copy, and validate editor-content results against the current editor body before Apply.
- Hide insert/replace and follow-up AI action controls while a transcription AI result is pending, and clear pending transcription results when the buffer is reset or a new recording attempt starts.
- Snapshot diary summary input before sending the AI request so returned summaries are fingerprinted against the text that was actually sent.
- Clear stale pending results when a later AI action fails in the same target/source scope.
- Reuse the same user-facing recommendation error mapping for Explore error state and recommendation AI history.
- For diary summary generation:
  - Empty API key continues to fail closed before any network request.
  - Successful summary creates a pending `.summary` result but does not write `DiaryEntry.aiSummary` until the user applies it.
  - Applying a summary writes `currentEntry.aiSummary` and saves through the existing save path.
- For transcription AI actions:
  - Refine, expand, and summarize create pending `.refine`, `.expand`, or `.summary` results.
  - Generated text does not replace `transcribedText` until the user applies it.
  - Applying a transcription result writes `transcribedText`; existing insert/replace正文 buttons remain the explicit path from transcription text to diary body.
- Failure results are recorded in history with the same user-visible error messages used by current UI.
- Copy uses `UIPasteboard` from SwiftUI view code; ViewModel remains platform-light and owns only result state.

## Test Plan

- Unit tests cover `AIActionResult` success/failure factories and input preview truncation.
- Unit tests cover applying pending summary updates `DiaryEntry.aiSummary` only after explicit apply.
- Unit tests cover pending results per application target/source scope, stale pending cleanup after failures, stale result rejection, and applying a diary summary to the source diary after `currentEntry` changes.
- Unit tests cover applying pending transcription results updates `transcribedText` only after explicit apply, including editor-content stale-result rejection, chained results after accepted editor content, reset cleanup, and new-recording cleanup.
- Existing empty-key OpenAIService test remains the fail-closed network boundary.
- Local validation:
  - `git diff --check`
  - Markdown relative link check
  - secret scan
  - `xcodebuild -list -project EasyNote.xcodeproj`
  - `xcodebuild test` when a compatible simulator is available; otherwise record the local runtime error and rely on GitHub CI.

## Assumptions

- Current-session history is sufficient for this PR; persisted AI result history can be planned separately.
- Applying an AI result is a user action and should be idempotent for the same pending result.
- AI analysis for mood/tag suggestions can remain notification-based; this PR focuses on text-generating actions that would otherwise overwrite user-visible text.
