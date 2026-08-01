# EasyNote Architecture

EasyNote is a SwiftUI iOS app organized around a small set of UI, state, persistence, and service boundaries. The current repository is still a prototype, so this document records the architecture that exists now and the boundaries future refactors should preserve.

## App Composition

- `EasyNoteApp` owns app startup and delegates shared SwiftData `ModelContainer` creation to `PersistenceBootstrap`.
- `PersistenceBootstrap` publishes loading, ready, and failed startup state; `PersistenceRootView` installs the ready container or presents explicit retry/recovery actions.
- `ContentView` owns tab-level composition, shared theme state, and stable app-level ViewModel instances.
- `SettingsView` is the Settings composition root: it forwards `ModelContext`, `ScenePhase`, theme state, and one `SettingsDependencies` bundle to feature-owned sections.
- SwiftUI views receive ViewModels explicitly where possible and use environment objects for app-wide tab/theme state.
- UIKit/AppKit-style helpers should stay isolated in `Extensions/` or small view adapters.

## Data Model

SwiftData is the source of truth for local app data:

- `DiaryEntry`: diary title, content, mood, tags, timestamps, favorite state, optional audio URL, and AI summary.
- `TodoItem`: todo title, priority, deadline, notes, completion, recurrence, and creation date.
- `ChatSession` and `SessionMessage`: persisted AI exploration sessions and related note references.
- `TabSelectionManager`: transient UI coordination, not a persisted model.

The current store is created under the app documents directory as `EasyNote.store`.
`EasyNoteSchemaV1` is the first versioned schema. It owns frozen nested model definitions that retain the existing four entity names, fields, and relationships; file-scope aliases keep the app-facing `DiaryEntry`, `TodoItem`, `ChatSession`, and `SessionMessage` names unchanged. Current startup opens V1 without a staged migration plan so an identical pre-versioned store is adopted and stamped without rebuilding. `EasyNoteMigrationPlan` contains V1 with no stages and is reserved for an adopted store and future schema versions.

Store-open failure never falls back to a new persistent store or resets files automatically. A user-confirmed rebuild first copies every existing `EasyNote.store`, `EasyNote.store-wal`, and `EasyNote.store-shm` component into a timestamped `Documents/EasyNoteRecovery` directory. Copy failure leaves the source untouched; rebuild failure keeps the recovery copy and remains visible for retry.

## ViewModel Layer

ViewModels coordinate UI state, SwiftData reads/writes, and service calls:

- `DiaryViewModel` owns diary list/current-entry state, speech integration, AI diary actions, and CloudKit sync entry points.
- `TodoViewModel` owns focused todo CRUD, recurrence behavior, todo list state, and post-save routing to the active todo reminder mode.
- `ExploreViewModel` owns recommendation generation and recommendation cache state; it does not own todo CRUD.
- `ChatSessionViewModel` owns persisted chat sessions, session-bound request tasks, message history, and per-session request failures. Provider prompts and deterministic local fallbacks consume immutable diary/conversation snapshots rather than execution-time selection state.
- Chat-session deletion explicitly stages deletion of every related `SessionMessage` and the `ChatSession` in one context save; save failure rolls back the complete deletion.
- Chat save failures never publish or restore relationship objects from a rolled-back context. The ViewModel replaces that context from the same container, refetches sessions, and restores selection by UUID while request routing continues to use captured value identifiers.
- `ContentView` passes the shared SwiftData `ModelContext` into stable app-level ViewModels through its root view instead of relying on production nil-context fallback stores.
- Recurring todo completion is planned through a shared helper so todo entry points do not duplicate next-occurrence creation rules.
- Todo local reminder eligibility is derived through a pure planner; `TodoViewModel` only asks the injected notification scheduler to synchronize or cancel after successful SwiftData saves.
- Todo system reminder proposals are derived through the pure `SystemReminderAgent`; `TodoViewModel` only asks the injected EventKit writer to create, update, complete, or remove Apple Reminders after successful SwiftData saves.
- Todo list categories are projected through a pure `TodoFilter` helper before SwiftUI renders the selected segment.
- Diary review insights are projected through a pure `DiaryReviewProjection` helper from the full diary entry set, independent of active diary search and filters. It reports distinct tag totals separately from capped top-tag trends and normalizes legacy numeric mood values before aggregation.
- Existing-diary edits are staged in a pure `DiaryEditDraft`; `DiaryViewModel` applies content, mood, tags, and recording URL through one explicit save, while Cancel leaves the SwiftData model unchanged.

Future refactors should separate pure business logic and service protocols from SwiftUI/SwiftData state, but behavior should remain observable through the existing ViewModels until a plan replaces that boundary.
Current service interactions are routed through narrow protocols for AI, AI credentials, AI content consent, AI HTTP transport, speech recognition, CloudKit diary sync, backup import/export, local todo notification scheduling, and system Reminders writing so ViewModels and Settings sections can be tested with fakes without changing production defaults. `SettingsDependencies` groups the Settings protocols and stores but does not add service ownership or alter production implementations.

## Concurrency And Diagnostics

- UI-facing `ChatSessionViewModel`, `TodoViewModel`, `DiaryViewModel`, and `ExploreViewModel` state and SwiftData UI-context access are main-actor isolated.
- `SpeechRecognitionService` owns published state and every `AVAudioEngine` install/start/stop/teardown transition on the main actor. Framework callbacks carry an opaque session token through a lock-protected gate; teardown invalidates that token before removing the tap or cancelling recognition so stale callbacks cannot publish into a later recording.
- Audio input buffers remain on the framework tap callback. Each tap captures only its own request/file and checks the session gate before appending or writing.
- Todo reminder scheduling copies saved todos into `Sendable` value snapshots before the async handoff. Because the existing scheduler protocol accepts `[TodoItem]`, one compatibility bridge rehydrates private detached models from those values; UI-context SwiftData instances never cross the task boundary.
- `CloudKitService` and its preview publish observable state on the main actor. CloudKit and Combine callback closures return through explicit transport wrappers or main-actor tasks before touching that state.
- All production diagnostics under `EasyNote/` use categorized unified logging. Diary/chat text, full filesystem paths, API keys, raw provider errors, and stable user identifiers must never be logged.

## Service Layer

- `KeychainCredentialStore` owns the DeepSeek credential, Security.framework CRUD, and verified migration from the legacy `UserDefaults` key. Its generic-password item is device-only and available only while the device is unlocked.
- `AIContentConsentStore` owns a separate default-denied, revocable permission to send selected diary or transcription text, plus recent diary fields used for recommendations, to DeepSeek. Credential presence or migration never grants consent.
- `OpenAIService` is the DeepSeek-compatible chat-completions client. It reads credentials and consent through injected protocols and must reject missing-key or unconsented requests before delegating to its injected HTTP client.
- `BackupService` owns local JSON backup export/import for SwiftData records and supported local voice recording files.
- `LocalTodoNotificationService` owns iOS local notification authorization state and async todo reminder scheduling/cancellation through an injectable UserNotifications adapter.
- `SystemReminderService` owns EventKit Reminders authorization state and serialized async writes of EasyNote-marked reminders to the user's default Apple Reminders list. EventKit callbacks are bounded by a single-resume 10-second timeout bridge.
- `SpeechRecognitionService` owns microphone/speech permissions, recording state, transcription updates, and serialized audio-engine lifecycle transitions.
- `CloudKitService` owns CloudKit interactions, but Debug currently defaults to simulation mode.
- `CloudKitSyncPreflight` owns the pure readiness checklist for future real CloudKit enablement without sending network requests or changing app storage.

Services may publish state for the UI, but provider-specific response shapes and side effects should not leak into views.

## UI Layer

SwiftUI views are grouped by feature:

- Diary: list, create, edit, detail, mood/tag/editor helpers, markdown rendering.
- Todo and recommendations: todo detail/edit, unified add flow, Explore screen.
- AI exploration: chat screen and session list.
- Settings: a composition shell plus feature-owned appearance, AI Keychain/consent, reminder, backup, and sync-preflight sections.

Views should remain presentation-focused. Persistence, AI calls, and recurrence behavior belong in ViewModels or services.

## Validation

- `xcodebuild -list -project EasyNote.xcodeproj` proves the project and scheme are readable.
- GitHub Actions CI runs whitespace checks, project listing, simulator selection, and `xcodebuild test`.
- Focused unit tests cover model-level recurrence and chat-session behavior.

## Related Docs

- [Interfaces](interfaces.plan.md)
- [MVP Acceptance](mvp-acceptance.plan.md)
- [Source Notes](src/README.md)
