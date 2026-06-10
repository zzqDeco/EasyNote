# EasyNoteApp.swift

## Responsibility

- Own the SwiftUI app entry point and shared SwiftData `ModelContainer`.
- Define the current local store path and model schema used by the app.
- Save the main context when the app enters the background.

## Boundaries

- Do not add view-specific state here; tab/theme/session state belongs in `ContentView` and ViewModels.
- Do not add provider clients or CloudKit sync orchestration here; those belong in `Services/` and ViewModels.

## Behavior Notes

- The shared SwiftData store is explicitly placed at `URL.documentsDirectory/EasyNote.store`.
- The app-level `ModelConfiguration` uses `cloudKitDatabase: .none`; CloudKit sync remains owned by `CloudKitService`, not SwiftData automatic sync.
- The schema currently includes diary, todo, chat session, and session message models.
- Startup prints local paths for prototype debugging; production logging should be planned before broad cleanup.

## Tests

- Run `xcodebuild -list -project EasyNote.xcodeproj` after project or app-entry changes.
- Run `xcodebuild test` after schema changes when a compatible simulator runtime is available.
