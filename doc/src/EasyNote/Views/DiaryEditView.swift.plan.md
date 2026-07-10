# DiaryEditView.swift

## Responsibility

- Present existing-diary editing through a local `DiaryEditDraft`.
- Coordinate explicit Done, discard confirmation, transcription application, and pending recording capture.

## Boundaries

- Do not mutate `DiaryEntry` while the user is editing.
- Do not persist from content changes, mood/tag sheets, transcription callbacks, recording stop, or `onDisappear`.

## Behavior Notes

- Done dismisses only after the atomic ViewModel commit succeeds; failures keep the draft visible and show an alert.
- Discard and unresolved disappearance remove only the pending replacement recording and preserve the original entry and recording.
- Accepted AI text remains in the transcription buffer until the user explicitly inserts or replaces draft content.

## Tests

- Unit tests cover the draft and commit boundaries; manual smoke verifies Done, discard, save failure, and recording replacement behavior.
