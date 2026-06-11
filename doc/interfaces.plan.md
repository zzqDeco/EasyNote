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
- `TodoItem.recurringInterval` stores a `TodoItem.RecurringInterval.rawValue` string, currently Chinese display values such as `每天` and `每周`.
- Recurring todo completion must use the shared recurrence planner. A next todo is created only after a completed recurring item has both a valid stored interval and a deadline.
- `ChatSession.messages` owns the session message list; `SessionMessage.relatedEntryIds` stores diary UUID strings, not relationships.
- `EasyNoteApp` creates the app `ModelContainer` with a named local `ModelConfiguration`, `url: URL.documentsDirectory/EasyNote.store`, and `cloudKitDatabase: .none`.

Model changes require a migration or compatibility note before implementation.

Core SwiftData save paths should return a success value or set a user-visible `errorMessage`; production code should not silently swallow diary, todo, or chat save failures. Failed saves should roll back the active `ModelContext` so pending inserts, deletes, and relationship edits cannot be persisted by a later unrelated save.

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

## Speech Boundary

`SpeechRecognitionService` owns:

- `SFSpeechRecognizer` configured for `zh-CN`
- microphone/speech permission requests
- `RecordingState`
- published transcription text
- recording file URL validation

Views and ViewModels should not manage `AVAudioEngine` or `SFSpeechAudioBufferRecognitionRequest` directly.

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
