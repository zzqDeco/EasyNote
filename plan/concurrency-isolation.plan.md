# Concurrency Isolation And Privacy-Safe Logging

## Summary

- Isolate UI-facing state and audio lifecycle operations so strict Swift concurrency checks have explicit ownership boundaries.
- Replace ad hoc production console output in the owned scope with categorized, privacy-safe unified logging.

## Scope

- Mark UI-facing ViewModels as main-actor isolated and adjust affected callers and tests.
- Keep `SpeechRecognitionService` published state and `AVAudioEngine` lifecycle on the main actor, reject overlapping starts, and invalidate callbacks from ended sessions.
- Explicitly return diary audio delegate and list refresh callbacks to the main actor.
- Replace `print` calls in touched ViewModel, speech, and diary view files without logging diary/chat text, full paths, credentials, or stable user identifiers.
- Update architecture and source notes for the concurrency and privacy boundaries.
- Do not change Backup services/settings/protocols, AI credentials/settings, persistence schema, or AI feature behavior.

## Implementation

- Use `@MainActor` for UI-facing ViewModels and the speech service so published state, SwiftData UI contexts, and audio engine install/start/stop/teardown are serialized.
- Keep a lock-protected speech session gate available to non-main framework callbacks. A callback must match the active token before it can enqueue a main-actor state update; teardown invalidates the token before cancelling recognition or removing the input tap.
- Capture each recognition request and recording file for its input tap so late buffers cannot target a replacement session.
- Use `Logger` categories with static messages or non-sensitive counts/statuses only.
- Keep SwiftData models and service protocols unchanged to avoid overlap with adjacent Wave 3 workers.

## Test Plan

- Add focused tests for speech session activation, overlap rejection, invalidation, and stale callback rejection.
- Add a focused main-actor publication test for `TodoViewModel`.
- Run `git diff --check` and validate relative Markdown links.
- Run `xcodebuild -list -project EasyNote.xcodeproj`.
- Run generic simulator `build-for-testing` with `SWIFT_STRICT_CONCURRENCY=complete`.
- Run a generic-device Release build and inspect app-owned concurrency warnings in the owned scope.

## Assumptions

- Speech and microphone framework callbacks may arrive after cancellation and from non-main queues.
- Audio input buffers remain processed on the framework tap callback; only engine lifecycle and published state are main-actor owned.
- Hardware-dependent permission and live microphone behavior remain manual acceptance checks.
- Broader `Sendable` redesign of shared AI, Backup, and reminder protocols is outside this slice.
