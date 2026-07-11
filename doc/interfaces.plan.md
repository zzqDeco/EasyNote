# EasyNote Interfaces

This document records the current contracts that cross module boundaries in EasyNote.

## Local Settings

- DeepSeek API key: stored as a Keychain generic-password item with service `io.github.zzqDeco.EasyNote`, account `deepseek_api_key`, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- `openai_api_key`: legacy `UserDefaults` source only. It is removed only after the selected Keychain value is written and an exact read-back succeeds; migration failure leaves it intact.
- `ai_content_consent_granted`: separate `UserDefaults` boolean owned by `AIContentConsentStore`; absence is denied, and saving or migrating a key never changes it.
- `darkModeEnabled`: stored with `@AppStorage` in `ThemeManager`.
- `accentColorName`: stored with `@AppStorage` in `ThemeManager`.
- `todo_reminder_mode`: stored by `TodoReminderModeStore` as `off`, `localNotification`, or `systemReminderAgent`.
- `todo_notifications_enabled`: legacy-compatible local notification flag stored with `@AppStorage` in Settings and read by `LocalTodoNotificationService`.
- `todo_system_reminders_may_exist`: a `TodoReminderModeStore` handoff marker used only to decide whether returning to local notifications should clean EasyNote-marked Apple Reminders after a prior system-reminder mode.

The repository must not contain default API keys. Missing Keychain credentials or denied AI content consent disable AI calls with a user-visible error before network transport is invoked.

`SettingsDependencies` is the Settings composition contract for the credential store, AI content consent store, backup service, local notification scheduler, system reminder agent/writer, reminder-mode store, and CloudKit preflight report. `SettingsView` forwards this bundle and SwiftUI environment values to feature-owned sections; the bundle does not implement persistence behavior itself.

## SwiftData Models

- `DiaryEntry.id` is the stable diary identifier used by lists, filters, delete paths, and chat related-entry references.
- `DiaryEntry.tags` is stored as `[String]` and used by search/filter paths.
- Diary list search and filters are derived through `DiaryEntryQuery`; the fetched `diaryEntries` source list should not be overwritten just to show filtered results.
- `TodoItem.recurringInterval` stores a `TodoItem.RecurringInterval.rawValue` string, currently Chinese display values such as `每天` and `每周`. Reads also accept legacy English values such as `daily` and `weekly` through the shared recurrence parser.
- Recurring todo completion must use the shared recurrence planner. A next todo is created only after a completed recurring item has both a valid stored interval and a deadline.
- `ChatSession.messages` owns the session message list; `SessionMessage.relatedEntryIds` stores diary UUID strings, not relationships.
- `ChatSessionViewModel.deleteSession` explicitly deletes the session's message rows before the session row. These deletes share one save and one rollback boundary; this contract does not depend on an inverse relationship.
- `EasyNoteSchemaV1` owns frozen nested `DiaryEntry`, `TodoItem`, `ChatSession`, and `SessionMessage` model definitions at version `1.0.0`; file-scope aliases preserve the existing source-level names and persisted entity names.
- `EasyNoteMigrationPlan` declares V1 and currently has no migration stages.
- `PersistenceBootstrap` creates the current app `ModelContainer` with V1 and no staged plan, a named local `ModelConfiguration`, `url: URL.documentsDirectory/EasyNote.store`, and `cloudKitDatabase: .none`. This first-version open is the non-destructive adoption path for an identical pre-versioned store; the migration plan is used only after adoption and by future versions.

Model changes require a migration or compatibility note before implementation.

Core SwiftData save paths should return a success value or set a user-visible `errorMessage`; production code should not silently swallow diary, todo, or chat save failures. Failed saves should roll back the active `ModelContext` so pending inserts, deletes, and relationship edits cannot be persisted by a later unrelated save.

Todo creation views own a pure `TodoDraft` and do not construct or insert a `TodoItem` until explicit Save. Diary and todo create, edit, and detail-delete actions resolve the ViewModel result through `PersistenceFeedback`; success may dismiss or navigate away, while failure keeps the current screen and input visible with an error.

## Persistence Startup And Recovery Boundary

`PersistenceBootstrap.State` is `loading`, `ready(ModelContainer)`, or `failed(PersistenceBootstrapFailure)`. Initial open and retry use the same V1-without-plan configuration and store URL, allowing first-version adoption without deleting or rebuilding data. An adoption failure enters `failed` and requires the same explicit recovery confirmation as any other open failure. UI-test launches use V1 with an in-memory configuration.

Recovery rebuild is available only for the persistent store and only after explicit UI confirmation:

- create a unique UTC timestamp directory under `Documents/EasyNoteRecovery`
- copy each existing `EasyNote.store`, `EasyNote.store-wal`, and `EasyNote.store-shm` file into that directory
- abort before deletion if directory creation or any copy fails
- after all copies succeed, remove the original components and attempt a fresh V1 container open
- if removal or rebuild fails, publish failed state with the recovery directory location and do not delete the recovery copy

Container creation, current time, and file operations are injectable so unit tests can force open, retry, copy, and rebuild outcomes without touching user data. Recovery copies are raw SQLite store components for support/manual restoration; they are separate from the Settings JSON backup/import contract.

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
`BackupSettingsSection` consumes this behavior through `BackupServiceProviding` supplied by `SettingsDependencies`; the default implementation remains `BackupService`.

Backup v1 uses a single JSON file with `.easynotebackup` extension and root type `EasyNoteBackupV1`:

- `version`: currently `1`
- `exportedAt`
- `diaryEntries`
- `todoItems`
- `chatSessions`
- `sessionMessages`
- `audioAssets`

Diary backup records reference voice recordings through `audioAssetId`. Audio assets contain the original filename, supported extension, byte count, and base64-encoded file data. Only local `.caf` and `.m4a` recording files are exported.

Only messages referenced by exported chat sessions are included in `sessionMessages`; fetchable orphaned messages from deleted sessions are not exported. A message ID may belong to only one chat session. Export normalizes legacy cross-session message references by assigning duplicate references new backup-only UUIDs and copying their message payload, preserving both conversations while satisfying this contract. Decode and import apply the same normalization to older V1 files before strict validation, so previously accepted shared-message backups remain restorable without recreating unsupported shared SwiftData relationships. Unsupported versions, duplicate IDs unrelated to this legacy relationship, missing message/audio references, unsupported audio extensions, or malformed base64 data must fail without writing model changes. Same-ID model records are updated, missing same-type records are inserted, and local records absent from the backup are preserved. When an older backup is imported over a session with newer local messages, those local messages remain attached and the session modified time stays at the latest imported, existing, or preserved message timestamp. Restored audio files are written under the app Documents directory as `restored_recording_<uuid>.<ext>`.

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

Before creating the request publisher, `OpenAIService` must read a non-empty credential and observe granted consent. The injected `AIHTTPClientProviding` boundary must not be called when either condition fails. Consent is app-wide but revocable; revocation blocks subsequent requests immediately without deleting the Keychain credential.

Only the selected diary or transcription text is placed in the prompt body. Recording audio files are never attached. The DeepSeek API key is transmitted only in the HTTP Authorization header required for provider authentication and is never included in prompt content, response history, SwiftData, backups, or logs.

`CredentialStoreProviding` exposes throwing read, save, delete, and legacy-migration operations. `KeychainCredentialStore` performs Security.framework CRUD through an injectable adapter. Duplicate adds update only `kSecValueData`; deletes treat `errSecItemNotFound` as success. Migration preserves an existing non-empty Keychain value as authoritative, performs a write plus exact read-back, and removes the legacy defaults value only after verification.

Current response contract expects `choices[0].message.content`. Malformed or failed responses are mapped to `OpenAIError` and should become user-visible errors or controlled fallbacks.

Chat exploration captures a `ChatRequestContext` before sending. The context fixes the request UUID, target session UUID, conversation history, related diary IDs, and diary snapshots. User and assistant messages are written by target session ID; switching a session invalidates its in-flight request but preserves an already completed retryable failure, while clearing or deleting cancels only after the SwiftData mutation succeeds. A retry records whether the original user message was saved and re-saves it before contacting the provider when the first persistence attempt failed. The previous failure remains available until the retry succeeds or produces a replacement failure, so navigation cancellation cannot remove the retry path. Task cancellation propagates through the async publisher bridge to the underlying provider subscription. Provider failures may use `LocalDiaryQueryAnalyzer`, but only to report titles, dates, previews, moods, and counts present in the captured snapshots. Query cleanup retains the original term and adds a boundary-cleaned command-free term, including diary, note, record, mention-question, natural mood-summary, and built-in broad-summary wrappers; connector particles included in a removed wrapper are discarded without altering real subjects. Diary matching includes title, content, tags, explicit mood metadata, and non-stop-word single-character CJK topics. Recent and mood summaries apply any extracted topic scope before deriving local facts; broad summaries are reserved for unscoped requests. If no factual local result exists, the failure remains a retryable UI state and is not persisted as an assistant claim.

`AIResponseParser` owns the model-content parsing contract:

- Diary analysis accepts pure JSON, Markdown fenced JSON, or surrounding prose containing a JSON object with non-empty `moods` and `tags` arrays.
- Recommendations accept pure JSON, Markdown fenced JSON, surrounding prose containing a JSON object, or Chinese section/list output with recommendation and todo sections.
- Completely malformed diary analysis returns the stable default moods/tags.
- Completely malformed recommendations return the stable default recommendations/todos.

The parser is pure and must not read API keys, send network requests, or inspect provider transport metadata.
ViewModels consume AI behavior through `OpenAIServiceProviding`. The protocol exposes request methods, Keychain-backed API key access, and an erased processing-state publisher without exposing concrete `@Published` storage.

## AI Result Confirmation Boundary

`AIActionResult` records current-session AI outcomes without changing SwiftData schema. Results include an action type (`summary`, `refine`, `expand`, `analyze`, or `recommendation`), an application target, optional source entity id, input source, input fingerprint, input preview, output text, timestamp, success state, and optional failure message.

Text-generating diary and transcription actions must not mutate persisted diary fields or `transcribedText` until the user applies the pending result. Copy is UI-only; discard removes the pending result from current-session history without mutating diary data. Recommendation results are reviewable/copyable history entries and are not directly applied through this boundary. Missing API keys and denied consent still fail closed before network requests and may record a failure result, but must not create a successful pending result.

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
