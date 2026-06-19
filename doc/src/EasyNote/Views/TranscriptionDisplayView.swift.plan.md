# TranscriptionDisplayView.swift

## Responsibility

- Present speech recording state, permission status, transcription text, pending AI text results, current-session AI history, and AI text actions.
- Offer explicit insert and replace actions for the parent diary view to apply transcription to its current draft.

## Boundaries

- Do not mutate diary body text directly.
- Do not manage microphone permissions, `AVAudioEngine`, or speech-recognition requests.
- Do not save SwiftData entries.

## Behavior Notes

- Raw transcription is displayed from `DiaryViewModel.transcribedText`; AI-processed text is displayed as a pending result until the user applies it.
- Insert/replace actions are routed through a closure supplied by the parent view.
- Permission failure and recording errors must be visible without clearing typed content.
- Apply/copy/discard controls act on `AIActionResult` and must not write diary body text directly.

## Tests

- `EasyNoteTests` covers the pure draft composition helper and ViewModel apply helpers used by the view actions.
- Real permission and recording behavior remains manual device/simulator smoke coverage.
