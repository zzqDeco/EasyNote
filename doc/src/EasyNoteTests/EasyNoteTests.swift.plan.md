# EasyNoteTests.swift

## Responsibility

- Hold focused unit tests for core model behavior that does not need UI or live services.

## Boundaries

- Do not add live network, CloudKit, microphone, or simulator-permission tests here.
- Do not rely on persisted user data or host machine state.

## Behavior Notes

- Current tests cover todo recurrence date calculation.
- Current tests cover legacy/current recurrence parsing, unsubmitted todo draft cancellation, persistence dismissal decisions, and idempotent keyboard observer registration.
- Current tests cover todo notification eligibility and `TodoViewModel` scheduler integration through fakes.
- Current tests cover system reminder agent skip/lead-time decisions, reminder mode migration, and `TodoViewModel` EventKit-writer routing through fakes.
- Current tests cover chat-session title summary plus non-empty title/content and non-future timestamp integrity behavior.
- Current tests cover AI action result success/failure records, input matching, per-target/source pending state, stale pending cleanup after failures, source-bound diary summary application, stale result rejection, and explicit diary/transcription application behavior.
- Current tests cover CloudKit preflight readiness as pure local logic; they do not contact CloudKit.
- Current tests cover existing-diary draft save/discard/rollback, canonical mood storage, transcription isolation, and original/pending recording ownership.
- The main unit-test suite is main-actor isolated when it directly exercises UI-facing ViewModels.
- Focused concurrency coverage verifies speech-session overlap rejection/invalidation and main-thread Todo publication without accessing microphone hardware.

## Tests

- Run through GitHub Actions on a compatible macOS/Xcode/simulator combination.
- Run locally with `xcodebuild test` when the installed simulator runtime matches the selected SDK.
