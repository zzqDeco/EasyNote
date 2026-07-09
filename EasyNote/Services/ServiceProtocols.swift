//
//  ServiceProtocols.swift
//  EasyNote
//

import Combine
import Foundation
import SwiftData

protocol OpenAIServiceProviding: AnyObject {
    var apiKey: String { get set }
    var isProcessingPublisher: AnyPublisher<Bool, Never> { get }

    func generateSummary(from text: String) -> AnyPublisher<String, OpenAIError>
    func refineTranscription(text: String) -> AnyPublisher<String, OpenAIError>
    func analyzeDiaryContent(text: String) -> AnyPublisher<(moods: [String], tags: [String]), OpenAIError>
    func expandText(text: String) -> AnyPublisher<String, OpenAIError>
    func summarizeText(text: String) -> AnyPublisher<String, OpenAIError>
    func chat(prompt: String) async throws -> String
    func generateRecommendations(from diaryContent: String) -> AnyPublisher<(recommendations: [String], todos: [String]), OpenAIError>
}

protocol SpeechRecognitionProviding: AnyObject {
    var transcribedTextPublisher: AnyPublisher<String, Never> { get }
    var recordingStatePublisher: AnyPublisher<RecordingState, Never> { get }
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }
    var speechPermissionStatusPublisher: AnyPublisher<SpeechPermissionStatus, Never> { get }
    var microphonePermissionStatusPublisher: AnyPublisher<MicrophonePermissionStatus, Never> { get }

    func requestPermissions(completion: ((Bool) -> Void)?)
    func startRecording() throws
    func stopRecording() throws
    func saveRecordingWithTranscription() -> (audioURL: URL?, transcription: String)
}

protocol CloudKitDiarySyncProviding: AnyObject {
    func syncDiaryEntries(entries: [DiaryEntry]) -> AnyPublisher<Void, Error>
    func fetchDiaryEntries() -> AnyPublisher<[DiaryEntry], Error>
}

protocol BackupServiceProviding {
    func exportBackup(from modelContext: ModelContext, exportedAt: Date) throws -> EasyNoteBackupV1
    func encodeBackup(_ backup: EasyNoteBackupV1) throws -> Data
    func decodeAndValidateBackup(from data: Data) throws -> EasyNoteBackupV1
    func summary(for backup: EasyNoteBackupV1) -> BackupSummary
    func importBackup(_ backup: EasyNoteBackupV1, into modelContext: ModelContext) throws -> BackupImportResult
}

extension BackupServiceProviding {
    func exportBackup(from modelContext: ModelContext) throws -> EasyNoteBackupV1 {
        try exportBackup(from: modelContext, exportedAt: Date())
    }
}

protocol TodoNotificationSchedulingProviding: AnyObject {
    var authorizationStatusPublisher: AnyPublisher<TodoNotificationAuthorizationStatus, Never> { get }

    func refreshAuthorizationStatus()
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func synchronizeNotification(for todo: TodoItem)
    func reconcileNotifications(for todos: [TodoItem])
    func cancelNotification(forTodoID id: UUID)
    func cancelAllTodoNotifications()
}

protocol SystemReminderWritingProviding: AnyObject {
    var authorizationStatusPublisher: AnyPublisher<SystemReminderAuthorizationStatus, Never> { get }

    func refreshAuthorizationStatus()
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func applyProposal(_ proposal: SystemReminderProposal, completion: @escaping (Result<SystemReminderWriteResult, SystemReminderError>) -> Void)
    func completeReminder(forTodoID id: UUID, completion: ((Result<Void, SystemReminderError>) -> Void)?)
    func removeReminder(forTodoID id: UUID, completion: ((Result<Void, SystemReminderError>) -> Void)?)
}
