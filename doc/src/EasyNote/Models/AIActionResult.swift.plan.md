# AIActionResult.swift

## Responsibility

- Represent current-session AI action outcomes as pure value data.
- Capture action type, application target, optional source entity id, input source, input fingerprint, input preview, output text, timestamp, success state, and optional failure message.

## Boundaries

- Do not persist AI history through SwiftData in this slice.
- Do not store provider request/response payloads, API keys, or raw transport metadata.
- Do not perform pasteboard, network, or SwiftData save work from this model.

## Behavior Notes

- Successful diary summary and transcription results can become pending results that require explicit user application.
- Diary summary results carry the source `DiaryEntry.id` so pending results cannot be applied to a different entry after navigation.
- Transcription results carry an input source so editor-content AI results can be revalidated against current editor text instead of only the copied transcription buffer.
- Text-generating results carry a deterministic input fingerprint so stale results can be rejected if source text changes before Apply.
- Recommendation results are recorded for review and copy, but are not directly applied through this model.
- Input previews are normalized and truncated so history can be shown without exposing long raw prompts.

## Tests

- `EasyNoteTests` covers success/failure state, apply eligibility, input matching, and preview truncation.
