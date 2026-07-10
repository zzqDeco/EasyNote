# EasyNote Interfaces

This document records the current contracts that cross module boundaries in EasyNote.

## Local Settings

- `openai_api_key`: stored in `UserDefaults` through the Settings screen and read by `OpenAIService`.
- `darkModeEnabled`: stored with `@AppStorage` in `ThemeManager`.
- `accentColorName`: stored with `@AppStorage` in `ThemeManager`.
- `todo_reminder_mode`: stored by `TodoReminderModeStore` as `off`, `localNotification`, or `systemReminderAgent`.
- `todo_notifications_enabled`: legacy-compatible local notification flag stored with `@AppStorage` in Settings and read by `LocalTodoNotificationService`.
- `todo_system_reminders_may_exist`: a `TodoReminderModeStore` handoff marker used only to decide whether returning to local notifications should clean EasyNote-marked Apple Reminders after a prior system-reminder mode.

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

## Diary Edit Transaction Boundary

Existing-diary editing uses `DiaryEditDraft` instead of mutating `DiaryEntry` as the user types. The draft snapshots content, canonical mood, tags, and original audio URL, and may own one pending replacement recording.

- Content, mood, tags, transcription insertion/replacement, accepted transcription AI output, and recording capture stay in the draft until Done.
- `DiaryViewModel.commitEditDraft` resolves the entry by stable UUID, applies all draft fields, and performs exactly one SwiftData save.
- A failed save rolls back, exposes a user-visible error, keeps the editor and pending recording available for retry, and leaves the original recording untouched.
- Successful replacement deletes the previously saved local recording only after the new URL commits.
- Cancel or unresolved disappearance cancels the active recognition session, clears its shared transcription buffer, deletes any unclaimed or pending replacement recording, and never persists draft fields.
- `MoodCatalog` maps picker integers and legacy numeric strings to canonical Chinese labels; existing non-empty Chinese labels remain valid inputs.

## Todo Notification Boundary

Todo reminder notifications are derived from existing todo fields and do not add SwiftData schema:

- global local-notification enablement is controlled by `todo_notifications_enabled`
- active reminder behavior is controlled by `todo_reminder_mode`
- a todo is eligible only when it is incomplete and has a future `deadline`
- notification identifiers use `TodoItem.id` through the stable `easynote.todo.<uuid>` prefix
- completing or deleting a todo cancels its notification
- editing, creating, restoring, or uncompleting a todo synchronizes the notification to the current todo state
- completing a recurring todo cancels the original notification and synchronizes the generated next todo
- reconciliation retains at most 64 pending todo reminders, prioritizing the nearest future deadlines and canceling non-retained reminder identifiers

`TodoNotificationPlanner` owns pure eligibility, identifier, and retained-slot selection rules. `LocalTodoNotificationService` owns `UNUserNotificationCenter`, authorization status publishing, permission requests, pending notification writes, and cancellation through async/throws operations and an injectable adapter. Same-todo remove/add mutations are serialized so overlapping edits cannot let an older deadline replace or remove the newer request. Notification add failures are surfaced as `TodoNotificationError.schedulingFailed`; authorization denial remains separate. `TodoViewModel` only reconciles or cancels after SwiftData saves succeed, and reminder failure never rolls back a saved todo. UI tests must not depend on live permission prompts; focused unit tests use fake schedulers or notification-center adapters.

`TodoReminderModeStore` maps a missing `todo_reminder_mode` plus `todo_notifications_enabled == true` to `.localNotification` so existing local notification settings are preserved. Setting `.localNotification` writes the legacy flag to true; setting `.off` or `.systemReminderAgent` writes it to false. Successful system reminder writes or completions mark that EasyNote-created Apple Reminders may exist; successful handoff cleanup back to local notifications clears that marker.

## System Reminders Boundary

System Reminders mode lets EasyNote write eligible todos into Apple Reminders through EventKit without changing SwiftData schema. It is mutually exclusive with EasyNote local notifications:

- `.off`: do not schedule local notifications and do not write new system reminders
- `.localNotification`: reconcile EasyNote local notifications and do not write system reminders; when switching from system mode, or from off after system mode may have written reminders, Settings attempts to remove EasyNote-marked Apple Reminders for current todos so the same todo is not owned by two alert systems
- `.systemReminderAgent`: cancel EasyNote local todo notifications, then write/update Apple Reminders through the system reminder agent and writer; when access is already granted, Settings syncs current todos immediately so existing local notifications are replaced instead of dropped. If Settings has not yet received the current Reminders authorization value, it syncs after the publisher reports writable access.

`SystemReminderAgent` is pure logic. It reads only a todo, the active mode, and `SystemReminderContext` with `now` plus `Calendar`, and returns a `SystemReminderProposal`:

- completed todos skip with `.completedTodo`
- missing deadlines skip with `.missingDeadline`
- non-future or less-than-60-second deadlines skip with `.deadlineNotFuture`
- empty trimmed titles skip with `.emptyTitle`
- meeting/call keywords lead by 30 minutes
- travel keywords lead by 2 hours
- submission/deadline keywords lead by 24 hours when the deadline is more than 24 hours away, otherwise 2 hours
- preparation keywords lead by 1 hour
- other todos lead by 15 minutes
- lead times that would be in the past clamp to `now + 60 seconds` when the deadline is still far enough away

`SystemReminderProposalReconciler` maps proposals to side effects: create/update proposals apply through EventKit, completed-todo skips complete the marked reminder, missing/past/empty-title skips remove the marked reminder, and disabled-mode skips are ignored. This mapping is shared by ViewModel save/reload paths and Settings manual sync.

System reminders are identified by an EasyNote marker in notes:

```text
EasyNoteTodoID:<uuid>
```

`SystemReminderService` owns EventKit and stays behind the async/throws `SystemReminderWritingProviding` boundary. Fetch callbacks use a checked-continuation bridge with a 10-second production timeout, while the user-controlled authorization prompt has a separate five-minute timeout; timeout, cancellation, restricted/denied access, missing default list, and EventKit failures remain distinct. Late callbacks are ignored after the first terminal result. Complete read-modify-write operations are serialized, so applying a proposal updates one existing marked reminder or creates one and removes duplicates without concurrent marker races. EventKit failures are user-visible reminder errors and never roll back successful SwiftData saves.

## Local Backup Boundary

`BackupService` owns local export and import for the public, local-first MVP.
`SettingsView` consumes this behavior through `BackupServiceProviding`; the default implementation remains `BackupService`.

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

Chat exploration captures a `ChatRequestContext` before sending. The context fixes the request UUID, target session UUID, conversation history, related diary IDs, and diary snapshots. User and assistant messages are written by target session ID; switching a session invalidates its in-flight request but preserves an already completed retryable failure, while clearing or deleting cancels only after the SwiftData mutation succeeds. A retry records whether the original user message was saved and re-saves it before contacting the provider when the first persistence attempt failed. Task cancellation propagates through the async publisher bridge to the underlying provider subscription. Provider failures may use `LocalDiaryQueryAnalyzer`, but only to report titles, dates, previews, moods, and counts present in the captured snapshots. Query cleanup retains the original term and adds a boundary-cleaned command-free term, including diary, note, and record wrappers, so command phrases can be removed without corrupting real subjects. Recent and mood summaries apply any extracted topic scope before deriving local facts; broad summaries are reserved for unscoped requests. If no factual local result exists, the failure remains a retryable UI state and is not persisted as an assistant claim.

`AIResponseParser` owns the model-content parsing contract:

- Diary analysis accepts pure JSON, Markdown fenced JSON, or surrounding prose containing a JSON object with non-empty `moods` and `tags` arrays.
- Recommendations accept pure JSON, Markdown fenced JSON, surrounding prose containing a JSON object, or Chinese section/list output with recommendation and todo sections.
- Completely malformed diary analysis returns the stable default moods/tags.
- Completely malformed recommendations return the stable default recommendations/todos.

The parser is pure and must not read API keys, send network requests, or inspect provider transport metadata.
ViewModels consume AI behavior through `OpenAIServiceProviding`. The protocol exposes request methods, API key access, and an erased processing-state publisher without exposing concrete `@Published` storage.

## AI Result Confirmation Boundary

`AIActionResult` records current-session AI outcomes without changing SwiftData schema. Results include an action type (`summary`, `refine`, `expand`, `analyze`, or `recommendation`), an application target, optional source entity id, input source, input fingerprint, input preview, output text, timestamp, success state, and optional failure message.

Text-generating diary and transcription actions must not mutate persisted diary fields or `transcribedText` until the user applies the pending result. Copy is UI-only; discard removes the pending result from current-session history without mutating diary data. Recommendation results are reviewable/copyable history entries and are not directly applied through this boundary. Empty API keys still fail closed before network requests and may record a failure result, but must not create a successful pending result.

Pending text results are tracked by application target plus source entity id. Diary summary results must be bound to the `DiaryEntry.id` that produced them, and views must only render/apply summary results for that source entry. Applying diary summary or transcription results must verify that the current source text still matches the recorded input fingerprint. Transcription results launched from editor content must validate against the current editor text, not only the copied `transcribedText` buffer. Failed actions clear stale pending results for the same target/source scope.

Resetting or replacing the transcription buffer, or starting a new recording attempt, clears pending transcription AI results. Pending transcription results hide insert/replace and follow-up AI action controls until the user applies or discards the pending result. Accepted transcription `.refine` results update `transcribedText` first and then run the existing refined-content analysis path so mood/tag suggestions remain tied to text the user explicitly accepted. Expand and summary transcription results do not trigger this analysis. Once an editor-content result is accepted into the transcription buffer, follow-up AI actions validate against that accepted buffer text rather than the original editor body.

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
`DiaryViewModel` consumes speech behavior through `SpeechRecognitionProviding`, including erased publishers for transcription, recording state, recording activity, and permission status.

`cancelRecording()` invalidates the active recognition session before cancelling it, deletes any recording file that has not been transferred to a diary draft, and clears published transcription state. A late Speech callback from the cancelled session must not repopulate the next editor's shared transcription buffer.

Transcription content is not written into diary body text automatically. Views must apply transcribed or AI-refined text through an explicit insert or replace action, using the shared diary draft composition helper. Insert/replace actions should stay unavailable while speech recognition is still recording or processing partial results.

Draft recording files are owned by diary save flows after capture. Unsaved new-entry drafts should delete their pending local `.caf` file on dismissal, superseded draft recordings should be deleted before their URL is overwritten, deleting a diary entry should remove its saved local `.caf` or legacy `.m4a` after the model delete saves, and replacing an existing diary recording should remove the previously referenced local `.caf` or legacy `.m4a` only after the new reference is saved successfully. A failed existing-entry save retains both the original and pending replacement so the visible draft can retry; discarding that draft then removes only the pending replacement. New-entry save and dismiss paths should capture both active recordings and recordings that have already reached `finished`.

## CloudKit Boundary

`CloudKitService` owns CloudKit account checks, audio file sync, diary sync, and quota/user-id helpers. Debug mode currently sets simulation mode and reports iCloud unavailable for free-developer-account workflows.
`DiaryViewModel` consumes the current diary sync entry points through `CloudKitDiarySyncProviding`; real sync behavior remains owned by `CloudKitService`.

`CloudKitSyncPreflight` owns the readiness contract for future real sync enablement. The current project report is intentionally blocked:

- app entitlements do not declare iCloud/CloudKit services or the target container
- Debug builds still force simulation mode
- SwiftData automatic CloudKit sync remains disabled through `cloudKitDatabase: .none`
- CloudKit Dashboard schema deployment is not verified
- downloaded records do not yet prove stable `recordName` to `DiaryEntry.id` round-trip
- real account/device manual validation is not complete

The current service-managed target container is `iCloud.io.github.zzqDeco.EasyNote`. Future enablement must keep `DiaryEntry.id.uuidString` as the CloudKit record name, preserve local UUIDs on download, use `DiaryEntry.lastModified` as the conflict precedence boundary, and validate upload, download, conflict, offline failure, and recovery paths. If a future PR chooses SwiftData automatic CloudKit sync instead, it must be treated as a separate migration plan because the current app-level `ModelConfiguration` deliberately disables automatic sync.

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
