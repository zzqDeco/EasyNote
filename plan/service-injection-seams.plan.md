# Service Injection Seams

## Summary

- Add narrow service protocols so ViewModels and Settings can depend on behavior contracts instead of concrete service classes.
- Keep this as an internal refactor slice: no SwiftData schema changes, no provider changes, and no user-visible behavior changes.

## Scope

- Add protocols for AI, speech recognition, CloudKit diary sync, and backup import/export.
- Update `DiaryViewModel`, `ExploreViewModel`, and `SettingsView` to accept services through initializer defaults.
- Update architecture/interface/source docs to record the new service seam.
- Non-goals: large dependency-injection framework, persisted model changes, real CloudKit enablement, or AI provider configuration.

## Implementation

- Introduce `ServiceProtocols.swift` under `EasyNote/Services/`.
- Keep production defaults as `OpenAIService()`, `SpeechRecognitionService()`, `CloudKitService()`, and `BackupService()`.
- Expose `AnyPublisher`-based state streams from service protocols so callers do not rely on concrete `@Published` storage.
- Preserve existing notification behavior, UserDefaults keys, backup file format, and DeepSeek endpoint.

## Test Plan

- Add a focused unit test using a fake AI service injected into `DiaryViewModel`.
- Run `git diff --check`.
- Run `xcodebuild -list -project EasyNote.xcodeproj`.
- Run local `xcodebuild test` only if a compatible named simulator destination is available; otherwise rely on GitHub CI for `EasyNoteTests`.
- Run Markdown relative link checks because docs change.
- Run secret scan for AI/settings-adjacent changes.

## Assumptions

- Existing production construction paths should continue to work through default initializer arguments.
- Settings backup injection is for testability and future UI tests; file picker behavior remains unchanged.
- CloudKit remains simulated/debug-limited until a dedicated sync preflight and enablement plan.
