# DiaryDraftComposer.swift

## Responsibility

- Own pure text composition for applying speech transcription to a diary draft.
- Provide explicit insert and replace modes shared by create/edit diary flows.

## Boundaries

- Do not read or write SwiftData.
- Do not inspect microphone, speech, AI, or CloudKit state.
- Do not mutate `DiaryViewModel.transcribedText`; callers own lifecycle cleanup.

## Behavior Notes

- Empty or whitespace-only transcription preserves the existing draft content.
- Replace mode returns the normalized transcription text.
- Insert mode appends transcription after a blank line when existing content is non-empty.

## Tests

- `EasyNoteTests` covers insert, replace, and empty-transcription preservation.
