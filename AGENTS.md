# AGENTS.md

Guidance for coding agents working in EasyNote.

## Project Overview

EasyNote is a SwiftUI iOS note-taking prototype with diary, todo, speech transcription, and DeepSeek-powered writing assistance.

- Language: Swift
- UI: SwiftUI
- Persistence: SwiftData
- Audio and speech: AVFoundation and Speech
- Optional sync boundary: CloudKit, currently simulated in Debug
- Tests: Xcode unit/UI test targets

## Commands

```bash
xcodebuild -list -project EasyNote.xcodeproj
xcodebuild -showdestinations -project EasyNote.xcodeproj -scheme EasyNote
xcodebuild test -project EasyNote.xcodeproj -scheme EasyNote -destination 'platform=iOS Simulator,name=<available simulator>'
```

If local simulator runtimes do not match the installed Xcode SDK, record the `xcodebuild` error and verify with the closest available build/list checks instead of treating it as a source regression.

For documentation-only changes, run at least:

```bash
git diff --check
```

## Architecture

- `EasyNote/EasyNoteApp.swift`: app entry point and SwiftData container setup.
- `EasyNote/Models/`: SwiftData models and shared state models.
- `EasyNote/ViewModels/`: UI-facing state, persistence operations, AI orchestration, and todo/diary flows.
- `EasyNote/Services/`: DeepSeek HTTP client, speech recognition, and CloudKit boundary.
- `EasyNote/Views/`: SwiftUI screens, editors, detail views, and shared UI components.
- `EasyNote/Extensions/`: small UIKit/SwiftUI helpers.
- `EasyNoteTests/`: unit tests for model and ViewModel behavior.
- `EasyNoteUITests/`: launch and UI smoke tests.
- `doc/`: current engineering documentation.
- `plan/`: active or recently delivered implementation plans.

## Product Rules

- The repository must not contain API keys or default cloud credentials.
- AI features must read the DeepSeek key from local settings and fail closed when the key is empty.
- Debug CloudKit behavior remains simulated unless a dedicated sync plan enables real iCloud containers.
- SwiftData migrations and model changes must be documented before implementation.
- User-visible setup or behavior changes must update `README.md`.

## Branching

- Stable branch: `main`
- Integration branch: `dev`
- Topic branches start from `dev`:
  - `feature/<desc>`
  - `fix/<desc>`
  - `docs/<desc>`
  - `refactor/<desc>`
  - `test/<desc>`
  - `chore/<desc>`
  - `release/<version>`

Routine changes should merge into `dev` first. Merge `dev` into `main` only after integration validation is clean.

## Commits

Use Conventional Commits:

```text
<type>(<scope>): <subject>
```

Common types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ci`, `build`.

Common scopes: `diary`, `todo`, `ai`, `speech`, `sync`, `settings`, `docs`, `tests`, `build`.

## Documentation Sync

For feature, fix, or refactor work:

1. Add or update a plan under `plan/` before implementing non-trivial behavior.
2. Update `doc/` when behavior, data flow, persistence, branch workflow, or verification rules change.
3. Update `README.md` for user-visible setup, configuration, or known limitations.
4. Update `doc/README.md` or `plan/README.md` when adding, retiring, or moving docs.

Keep stable current-state behavior in `doc/`; keep implementation intent, sequencing, and branch-local decisions in `plan/`.

## Review Checklist

- No API keys or private credentials are committed.
- SwiftData model changes include a migration or compatibility note.
- AI calls handle missing keys, network failure, and malformed responses.
- Speech/recording flows preserve permission handling and user-visible error states.
- Todo recurring behavior and diary/session model behavior have focused tests when changed.
- README, `doc/`, and `plan/` stay synchronized with the code change.
