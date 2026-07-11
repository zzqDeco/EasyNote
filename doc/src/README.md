# Source Notes

This directory contains short notes for important source files and subsystems. The notes record ownership boundaries, invariants, and testing concerns that are easy to lose during branch work. They are not a replacement for the source code.

The directory layout mirrors the repository layout. Put notes for Swift app files under `EasyNote/`, tests under `EasyNoteTests/`, and GitHub workflows under `.github/`. Use [the source note template](../templates/source-note.template.md) when adding a new note.

Source notes are required for public contracts, cross-module boundaries, persistence formats, AI/provider clients, speech/permission seams, CloudKit behavior, CI workflows, and files with non-obvious privacy behavior. They are not required for every SwiftUI view or every test file.

## App Entry And Models

- [EasyNoteApp](EasyNote/EasyNoteApp.swift.plan.md)
- [AIActionResult](EasyNote/Models/AIActionResult.swift.plan.md)
- [DiaryEditDraft](EasyNote/Models/DiaryEditDraft.swift.plan.md)
- [TodoDraft](EasyNote/Models/TodoDraft.swift.plan.md)
- [PersistenceFeedback](EasyNote/Models/PersistenceFeedback.swift.plan.md)
- [ChatRequestContext](EasyNote/Models/ChatRequestContext.swift.plan.md)
- [Models Overview](EasyNote/Models/README.plan.md)
- [SystemReminderAgent](EasyNote/Models/SystemReminderAgent.swift.plan.md)
- [TodoNotificationPlanner](EasyNote/Models/TodoNotificationPlanner.swift.plan.md)

## Services

- [AIResponseParser](EasyNote/Services/AIResponseParser.swift.plan.md)
- [BackupService](EasyNote/Services/BackupService.swift.plan.md)
- [CloudKitSyncPreflight](EasyNote/Services/CloudKitSyncPreflight.swift.plan.md)
- [LocalTodoNotificationService](EasyNote/Services/LocalTodoNotificationService.swift.plan.md)
- [OpenAIService](EasyNote/Services/OpenAIService.swift.plan.md)
- [ReminderServiceAdapters](EasyNote/Services/ReminderServiceAdapters.swift.plan.md)
- [ServiceProtocols](EasyNote/Services/ServiceProtocols.swift.plan.md)
- [SpeechRecognitionService](EasyNote/Services/SpeechRecognitionService.swift.plan.md)
- [SystemReminderService](EasyNote/Services/SystemReminderService.swift.plan.md)
- [CloudKitService](EasyNote/Services/CloudKitService.swift.plan.md)

## ViewModels And Views

- [ChatResponseGenerator](EasyNote/ViewModels/ChatResponseGenerator.swift.plan.md)
- [DiaryDraftComposer](EasyNote/ViewModels/DiaryDraftComposer.swift.plan.md)
- [TodoViewModel](EasyNote/ViewModels/TodoViewModel.swift.plan.md)
- [ViewModels Overview](EasyNote/ViewModels/README.plan.md)
- [Views Overview](EasyNote/Views/README.plan.md)
- [DiaryEditView](EasyNote/Views/DiaryEditView.swift.plan.md)
- [KeyboardObserver](EasyNote/Views/KeyboardObserver.swift.plan.md)
- [ChatExploreView](EasyNote/Views/ChatExploreView.swift.plan.md)
- [SettingsView](EasyNote/Views/SettingsView.swift.plan.md)
- [TranscriptionDisplayView](EasyNote/Views/TranscriptionDisplayView.swift.plan.md)

## Tests And CI

- [Unit Tests](EasyNoteTests/EasyNoteTests.swift.plan.md)
- [UI Tests](EasyNoteUITests/EasyNoteUITests.swift.plan.md)
- [GitHub CI Workflow](.github/workflows/ci.yml.plan.md)
- [GitHub UI Smoke Workflow](.github/workflows/ui-smoke.yml.plan.md)
