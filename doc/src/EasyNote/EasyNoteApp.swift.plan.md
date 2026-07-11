# EasyNoteApp.swift

## Responsibility

- Own the SwiftUI app entry point and retain the app-scoped `PersistenceBootstrap`.
- Install `PersistenceRootView`, which supplies the shared SwiftData `ModelContainer` only after bootstrap succeeds.
- Save the main context when the app enters the background.

## Boundaries

- Do not add view-specific state here; tab/theme/session state belongs in `ContentView` and ViewModels.
- Do not add provider clients or CloudKit sync orchestration here; those belong in `Services/` and ViewModels.

## Behavior Notes

- The shared SwiftData store path, schema, migration plan, and `cloudKitDatabase: .none` configuration belong to `PersistenceBootstrap` and `EasyNoteSchemaV1`.
- UI-test launches use an in-memory SwiftData configuration when `-easynote-ui-testing` or `EASYNOTE_UI_TESTING=1` is present.
- UI-test launches reset local defaults for API key, theme, and recommendation cache; production launches keep the persisted Documents store.
- Background save runs only when bootstrap has a ready container.
- Startup prints local paths for prototype debugging; production logging should be planned before broad cleanup.

## Tests

- Run `xcodebuild -list -project EasyNote.xcodeproj` after project or app-entry changes.
- Run `xcodebuild test` after schema changes when a compatible simulator runtime is available.
- Run local or manual hosted UI smoke after changing UI-test launch arguments or app-entry test isolation.
