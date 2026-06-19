# EasyNote Interfaces

This document records the current contracts that cross module boundaries in EasyNote.

## Local Settings

- `openai_api_key`: stored in `UserDefaults` through the Settings screen and read by `OpenAIService`.
- `darkModeEnabled`: stored with `@AppStorage` in `ThemeManager`.
- `accentColorName`: stored with `@AppStorage` in `ThemeManager`.

The repository must not contain default API keys. Empty `openai_api_key` disables AI calls with a user-visible error.

## SwiftData Models

- `DiaryEntry.id` is the stable diary identifier used by lists, filters, delete paths, and chat related-entry references.
- `DiaryEntry.tags` is stored as `[String]` and used by search/filter paths.
- Diary list search and filters are derived through `DiaryEntryQuery`; the fetched `diaryEntries` source list should not be overwritten just to show filtered results.
- `TodoItem.recurringInterval` stores a `TodoItem.RecurringInterval.rawValue` string, currently Chinese display values such as `每天` and `每周`.
- Recurring todo completion must use the shared recurrence planner. A next todo is created only after a completed recurring item has both a valid stored interval and a deadline.
- `ChatSession.messages` owns the session message list; `SessionMessage.relatedEntryIds` stores diary UUID strings, not relationships.
- `EasyNoteApp` creates the app `ModelContainer` with a named local `ModelConfiguration`, `url: URL.documentsDirectory/EasyNote.store`, and `cloudKitDatabase: .none`.

Model changes require a migration or compatibility note before implementation.

Core SwiftData save paths should return a success value or set a user-visible `errorMessage`; production code should not silently swallow diary, todo, or chat save failures. Failed saves should roll back the active `ModelContext` so pending inserts, deletes, and relationship edits cannot be persisted by a later unrelated save.

## Local Backup Boundary

`BackupService` owns local export and import for the public, local-first MVP.

Backup v1 uses a single JSON file with `.easynotebackup` extension and root type `EasyNoteBackupV1`:

- `version`: currently `1`
- `exportedAt`
- `diaryEntries`
- `todoItems`
- `chatSessions`
- `sessionMessages`
- `audioAssets`

Diary backup records reference voice recordings through `audioAssetId`. Audio assets contain the original filename, supported extension, byte count, and base64-encoded file data. Only local `.caf` and `.m4a` recording files are exported.

Only messages referenced by exported chat sessions are included in `sessionMessages`; fetchable orphaned messages from deleted sessions are not exported. Import validates the full backup before writing SwiftData. Unsupported versions, duplicate IDs, missing message/audio references, unsupported audio extensions, or malformed base64 data must fail without writing model changes. Same-ID model records are updated, missing same-type records are inserted, and local records absent from the backup are preserved. When an older backup is imported over a session with newer local messages, those local messages remain attached and the session modified time stays at the latest imported, existing, or preserved message timestamp. Restored audio files are written under the app Documents directory as `restored_recording_<uuid>.<ext>`.

## DeepSeek Chat-Completions Boundary

`OpenAIService` sends OpenAI-compatible requests to:

```text
POST https://api.deepseek.com/v1/chat/completions
```

Current request contract:

- `model`: `deepseek-chat`
- `messages`: one user message containing the task prompt
- `temperature`: `0.7`
- `max_tokens`: `500`
- Authorization: `Bearer <openai_api_key>`

Current response contract expects `choices[0].message.content`. Malformed or failed responses are mapped to `OpenAIError` and should become user-visible errors or controlled fallbacks.

`AIResponseParser` owns the model-content parsing contract:

- Diary analysis accepts pure JSON, Markdown fenced JSON, or surrounding prose containing a JSON object with non-empty `moods` and `tags` arrays.
- Recommendations accept pure JSON, Markdown fenced JSON, surrounding prose containing a JSON object, or Chinese section/list output with recommendation and todo sections.
- Completely malformed diary analysis returns the stable default moods/tags.
- Completely malformed recommendations return the stable default recommendations/todos.

The parser is pure and must not read API keys, send network requests, or inspect provider transport metadata.

## AI Result Confirmation Boundary

`AIActionResult` records current-session AI outcomes without changing SwiftData schema. Results include an action type (`summary`, `refine`, `expand`, `analyze`, or `recommendation`), an application target, optional source entity id, input preview, output text, timestamp, success state, and optional failure message.

Text-generating diary and transcription actions must not mutate persisted diary fields or `transcribedText` until the user applies the pending result. Copy is UI-only; discard removes the pending result from current-session history without mutating diary data. Recommendation results are reviewable/copyable history entries and are not directly applied through this boundary. Empty API keys still fail closed before network requests and may record a failure result, but must not create a successful pending result.

Pending text results are tracked per application target. Diary summary results must be bound to the `DiaryEntry.id` that produced them, and views must only render/apply summary results for that source entry.

## Speech Boundary

`SpeechRecognitionService` owns:

- `SFSpeechRecognizer` configured for `zh-CN`
- microphone/speech permission requests
- `RecordingState`
- observable speech permission state: authorized, denied, restricted, or not determined
- observable microphone permission state: granted, denied, or not determined
- published transcription text
- local recording file writing and URL validation

Views and ViewModels should not manage `AVAudioEngine` or `SFSpeechAudioBufferRecognitionRequest` directly.

Transcription content is not written into diary body text automatically. Views must apply transcribed or AI-refined text through an explicit insert or replace action, using the shared diary draft composition helper. Insert/replace actions should stay unavailable while speech recognition is still recording or processing partial results.

Draft recording files are owned by diary save flows after capture. Unsaved new-entry drafts should delete their pending local `.caf` file on dismissal, superseded draft recordings should be deleted before their URL is overwritten, deleting a diary entry should remove its saved local `.caf` or legacy `.m4a` after the model delete saves, and replacing an existing diary recording should remove the previously referenced local `.caf` or legacy `.m4a` only after the new reference is saved successfully. New-entry save and dismiss paths should capture both active recordings and recordings that have already reached `finished`.

## CloudKit Boundary

`CloudKitService` owns CloudKit account checks, audio file sync, diary sync, and quota/user-id helpers. Debug mode currently sets simulation mode and reports iCloud unavailable for free-developer-account workflows.

Real CloudKit enablement requires a dedicated plan covering entitlement, container, schema, merge, conflict, and validation behavior.

## GitHub Workflow Boundary

`.github/workflows/ci.yml` is the minimum CI contract:

- trigger on pushes to `main`, `dev`, and topic branches
- trigger on pull requests into `main` or `dev`
- use the hosted `macos-15` default Xcode/runtime pairing
- run whitespace checks, project listing, simulator selection, and focused unit tests

If hosted runner SDK/runtime availability changes, update [MVP Acceptance](mvp-acceptance.plan.md), the workflow source note, and the workflow in the same change.

## Related Docs

- [Architecture](architecture.plan.md)
- [MVP Acceptance](mvp-acceptance.plan.md)
- [Branching And Workflow](branching.md)
