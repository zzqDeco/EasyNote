# TranscriptionDisplayView.swift

## Responsibility

- Present speech recording state, permission status, transcription text, and AI text actions.
- Offer explicit insert and replace actions for the parent diary view to apply transcription to its current draft.

## Boundaries

- Do not mutate diary body text directly.
- Do not manage microphone permissions, `AVAudioEngine`, or speech-recognition requests.
- Do not save SwiftData entries.

## Behavior Notes

- Raw transcription and AI-processed text are displayed from `DiaryViewModel.transcribedText`.
- Insert/replace actions are routed through a closure supplied by the parent view.
- Permission failure and recording errors must be visible without clearing typed content.

## Tests

- `EasyNoteTests` covers the pure draft composition helper used by the view actions.
- Real permission and recording behavior remains manual device/simulator smoke coverage.
