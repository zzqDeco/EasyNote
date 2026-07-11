//
//  DiaryViewModel.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import Foundation
import SwiftData
import Combine
import SwiftUI
import OSLog

@MainActor
final class DiaryViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "EasyNote", category: "DiaryViewModel")
    // 服务
    private let speechService: any SpeechRecognitionProviding
    private let openAIService: any OpenAIServiceProviding
    private let cloudKitService: any CloudKitDiarySyncProviding
    
    // 数据状态
    @Published var diaryEntries: [DiaryEntry] = []
    @Published var currentEntry: DiaryEntry?
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published private(set) var transcriptionInputSource: AIActionResult.InputSource = .defaultText
    @Published var recordingState: RecordingState = .idle
    @Published var speechPermissionStatus: SpeechPermissionStatus = .notDetermined
    @Published var microphonePermissionStatus: MicrophonePermissionStatus = .notDetermined
    @Published var isProcessingAI = false
    @Published var aiActionHistory: [AIActionResult] = []
    @Published var pendingAIResults: [AIActionResult] = []
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var showToast = false
    @Published var diaryQuery = DiaryEntryQuery()
    
    // 取消令牌
    private var cancellables = Set<AnyCancellable>()
    var refinedContentAnalysisHandler: ((String) -> Void)?
    
    // 模型上下文
    private var modelContext: ModelContext
    private let saveModelContext: (ModelContext) throws -> Void
    
    // MARK: - 初始化方法
    
    init(
        modelContext: ModelContext?,
        speechService: (any SpeechRecognitionProviding)? = nil,
        openAIService: (any OpenAIServiceProviding)? = nil,
        cloudKitService: (any CloudKitDiarySyncProviding)? = nil,
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.speechService = speechService ?? SpeechRecognitionService()
        self.openAIService = openAIService ?? OpenAIService()
        self.cloudKitService = cloudKitService ?? CloudKitService()
        self.saveModelContext = saveModelContext

        if let context = modelContext {
            self.modelContext = context
        } else {
            // 如果没有提供ModelContext，创建一个内存中的临时ModelContext
            do {
                let container = try ModelContainer(for: DiaryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                self.modelContext = ModelContext(container)
            } catch {
                // 如果创建失败，创建一个临时的上下文（这在实际情况下可能会导致应用不稳定）
                Self.logger.fault("Failed to create fallback diary model context")
                fatalError("无法创建日记存储，应用程序无法继续")
            }
        }
        
        // 检查是否在预览环境中运行
        let isPreviewEnvironment = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        
        // 在预览环境中使用轻量级服务
        if isPreviewEnvironment {
            // 在预览中不绑定服务状态，避免不必要的处理
            Self.logger.debug("Using lightweight diary services in preview")
        } else {
            // 绑定语音服务状态
            self.speechService.transcribedTextPublisher
                .assign(to: &$transcribedText)
            
            self.speechService.recordingStatePublisher
                .assign(to: &$recordingState)
            
            self.speechService.isRecordingPublisher
                .assign(to: &$isRecording)

            self.speechService.speechPermissionStatusPublisher
                .assign(to: &$speechPermissionStatus)

            self.speechService.microphonePermissionStatusPublisher
                .assign(to: &$microphonePermissionStatus)
            
            // 绑定AI处理状态
            self.openAIService.isProcessingPublisher
                .assign(to: &$isProcessingAI)
            
            // 通过NotificationCenter观察CloudKitService的同步状态变化
            NotificationCenter.default.publisher(for: Notification.Name("CloudKitSyncStatusChanged"))
                .compactMap { $0.object as? Bool }
                .receive(on: RunLoop.main)
                .sink { [weak self] isSyncing in
                    self?.isSyncing = isSyncing
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .easyNoteBackupDidImport)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.loadEntries()
                }
                .store(in: &cancellables)
            
            // 加载日记条目
            loadDiaryEntries()
            loadLastSyncDate()
        
            // 检查是否需要进行模型迁移
            checkModelMigration()
        }
    }
    
    // MARK: - 模型迁移
    
    private func checkModelMigration() {
        // 如果有需要进行迁移的工作，可以在这里处理
        // 例如，在更改tags存储方式后，可能需要确保所有现有的条目都已正确迁移
        Self.logger.debug("Checked diary model compatibility")
    }
    
    // MARK: - 语音录制功能
    
    @discardableResult
    func startRecording() -> Bool {
        if speechPermissionStatus == .notDetermined || microphonePermissionStatus == .notDetermined {
            speechService.requestPermissions { [weak self] isGranted in
                guard let self else { return }
                if isGranted {
                    self.recordingState = .idle
                    self.errorMessage = nil
                    self.showToast(message: "语音和麦克风权限已开启，请再次点击语音输入开始录音")
                } else {
                    let message = self.speechPermissionStatus.failureMessage
                        ?? self.microphonePermissionStatus.failureMessage
                        ?? "语音录制权限未授权"
                    self.recordingState = .error(NSError(
                        domain: "SpeechRecognitionService",
                        code: 12,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    ))
                    self.errorMessage = message
                    self.showToast(message: message)
                }
            }
            return false
        }

        do {
            prepareTranscriptionForNewRecording()
            try speechService.startRecording()
            return true
        } catch {
            // 处理任何可能从语音服务抛出的错误
            self.errorMessage = "录音启动失败: \(error.localizedDescription)"
            self.showToast(message: error.localizedDescription)
            return false
        }
    }

    func prepareTranscriptionForNewRecording() {
        pendingAIResults.removeAll { $0.applicationTarget == .transcriptionText }
        transcriptionInputSource = .defaultText
    }
    
    func stopRecording() {
        do {
            try speechService.stopRecording()
        } catch {
            self.errorMessage = "停止录音失败: \(error.localizedDescription)"
        }
    }

    func cancelVoiceRecording() {
        speechService.cancelRecording()
        setTranscriptionText("")
    }

    @discardableResult
    func captureVoiceRecordingDraft() -> VoiceRecordingDraft {
        let (audioURL, transcription) = speechService.saveRecordingWithTranscription()

        if !transcription.isEmpty {
            setTranscriptionText(transcription)
        }

        return VoiceRecordingDraft(audioURL: audioURL, transcription: transcription)
    }

    static func removeRecordingFile(at url: URL?) {
        guard isRemovableLocalRecordingFile(url) else {
            return
        }

        guard let url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Self.logger.error("Failed to remove an unclaimed diary recording")
        }
    }

    static func isRemovableLocalRecordingFile(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else {
            return false
        }

        return ["caf", "m4a"].contains(url.pathExtension.lowercased())
    }

    static func removeReplacedRecordingFile(previous: URL?, replacement: URL?) {
        guard let previous else {
            return
        }

        if let replacement,
           previous.standardizedFileURL == replacement.standardizedFileURL {
            return
        }

        removeRecordingFile(at: previous)
    }

    func discardRecordingFile(at url: URL?) {
        Self.removeRecordingFile(at: url)
    }

    static func shouldCaptureVoiceRecordingDraft(isRecording: Bool, recordingState: RecordingState) -> Bool {
        if isRecording {
            return true
        }

        if case .finished = recordingState {
            return true
        }

        return false
    }

    func applyTranscription(to content: String, mode: DiaryTranscriptionApplyMode) -> String {
        let nextContent = DiaryDraftComposer.apply(
            transcription: transcribedText,
            to: content,
            mode: mode
        )

        if nextContent != content {
            setTranscriptionText("")
        }

        return nextContent
    }

    @discardableResult
    func applyTranscriptionToCurrentEntry(mode: DiaryTranscriptionApplyMode) -> Bool {
        guard let entry = currentEntry else {
            errorMessage = "没有正在编辑的日记"
            return false
        }

        let nextContent = applyTranscription(to: entry.content, mode: mode)
        guard nextContent != entry.content else {
            return true
        }

        return updateCurrentEntry(content: nextContent)
    }
    
    // MARK: - 日记管理
    
    @discardableResult
    func createNewEntry(title: String, creationDate: Date = Date()) -> Bool {
        let newEntry = DiaryEntry(title: title)
        newEntry.creationDate = creationDate
        newEntry.lastModified = creationDate
        modelContext.insert(newEntry)
        guard saveContext() else {
            return false
        }

        currentEntry = newEntry
        return true
    }
    
    @discardableResult
    func updateCurrentEntry(content: String? = nil, mood: String? = nil, tags: [String]? = nil) -> Bool {
        guard let entry = currentEntry else {
            errorMessage = "没有正在编辑的日记"
            return false
        }

        if let content {
            entry.content = content
        }

        if let mood {
            entry.mood = mood
        }

        if let tags {
            entry.tags = tags
        }

        entry.lastModified = Date()
        return saveContext()
    }

    @discardableResult
    func commitEditDraft(_ draft: DiaryEditDraft, forEntryID entryID: UUID) -> Bool {
        guard draft.entryID == entryID else {
            errorMessage = "日记草稿与当前条目不匹配"
            return false
        }

        if let replacementAudioURL = draft.pendingReplacementAudioURL {
            guard replacementAudioURL.isFileURL,
                  FileManager.default.fileExists(atPath: replacementAudioURL.path) else {
                errorMessage = "待保存的录音文件不存在"
                return false
            }
        }

        guard let entry = diaryEntry(withID: entryID) else {
            errorMessage = "未找到要保存的日记"
            return false
        }

        let previousContent = entry.content
        let previousMood = entry.mood
        let previousTags = entry.tags
        let previousAudioURL = entry.audioURL
        let previousLastModified = entry.lastModified
        entry.content = draft.content
        entry.mood = MoodCatalog.canonicalStoredLabel(draft.mood)
        entry.tags = draft.tags
        entry.audioURL = draft.resolvedAudioURL
        entry.lastModified = Date()

        guard saveContext(onFailure: {
            entry.content = previousContent
            entry.mood = previousMood
            entry.tags = previousTags
            entry.audioURL = previousAudioURL
            entry.lastModified = previousLastModified
        }) else {
            return false
        }

        if draft.pendingReplacementAudioURL != nil {
            Self.removeReplacedRecordingFile(
                previous: previousAudioURL,
                replacement: draft.pendingReplacementAudioURL
            )
        }
        return true
    }

    private func diaryEntry(withID entryID: UUID) -> DiaryEntry? {
        if currentEntry?.id == entryID {
            return currentEntry
        }

        if let loadedEntry = diaryEntries.first(where: { $0.id == entryID }) {
            return loadedEntry
        }

        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate<DiaryEntry> { entry in
                entry.id == entryID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    // MARK: - AI功能
    
    // 获取OpenAIService实例
    func getOpenAIService() -> any OpenAIServiceProviding {
        return openAIService
    }

    func setTranscriptionText(
        _ text: String,
        inputSource: AIActionResult.InputSource = .defaultText,
        clearsPendingResults: Bool = true
    ) {
        if clearsPendingResults {
            pendingAIResults.removeAll { $0.applicationTarget == .transcriptionText }
        }
        transcribedText = text
        transcriptionInputSource = inputSource
    }

    func recordAIActionResult(_ result: AIActionResult) {
        aiActionHistory.insert(result, at: 0)

        if result.canApply {
            pendingAIResults.removeAll { hasSamePendingScope($0, as: result) }
            pendingAIResults.insert(result, at: 0)
        } else {
            pendingAIResults.removeAll { hasSamePendingScope($0, as: result) }
        }
    }

    var pendingAIResult: AIActionResult? {
        pendingAIResults.sorted { $0.timestamp > $1.timestamp }.first
    }

    func pendingAIResult(
        for target: AIActionResult.ApplicationTarget,
        sourceEntityId: UUID? = nil
    ) -> AIActionResult? {
        pendingAIResults.first {
            $0.applicationTarget == target
                && (sourceEntityId == nil || $0.sourceEntityId == sourceEntityId)
        }
    }

    func recentAIResults(
        for target: AIActionResult.ApplicationTarget,
        sourceEntityId: UUID? = nil,
        limit: Int = 3
    ) -> [AIActionResult] {
        let pendingIds = Set(pendingAIResults.map(\.id))
        return Array(aiActionHistory
            .filter {
                $0.applicationTarget == target
                    && !pendingIds.contains($0.id)
                    && (sourceEntityId == nil || $0.sourceEntityId == sourceEntityId)
            }
            .prefix(limit))
    }

    func discardAIResult(_ result: AIActionResult) {
        pendingAIResults.removeAll { $0.id == result.id }
        aiActionHistory.removeAll { $0.id == result.id }
    }

    @discardableResult
    func applyAIResult(_ result: AIActionResult, currentEditorContent: String? = nil) -> Bool {
        guard result.canApply else {
            errorMessage = result.failureMessage ?? "没有可应用的AI结果"
            return false
        }

        switch result.applicationTarget {
        case .diarySummary:
            guard let entry = diaryEntry(for: result) else {
                errorMessage = "没有正在编辑的日记"
                return false
            }
            guard result.matchesInput(entry.content) else {
                pendingAIResults.removeAll { $0.id == result.id }
                errorMessage = "日记内容已变化，请重新生成AI摘要"
                return false
            }
            entry.aiSummary = result.outputText
            entry.lastModified = Date()
            guard saveContext() else {
                return false
            }
        case .transcriptionText:
            let sourceText = transcriptionValidationText(for: result, currentEditorContent: currentEditorContent)
            guard result.matchesInput(sourceText) else {
                pendingAIResults.removeAll { $0.id == result.id }
                errorMessage = result.inputSource == .editorContent
                    ? "当前编辑内容已变化，请重新生成AI结果"
                    : "转写内容已变化，请重新生成AI结果"
                return false
            }
            setTranscriptionText(result.outputText, clearsPendingResults: false)
            if result.actionType == .refine {
                analyzeAcceptedRefinedContent(result.outputText)
            }
        case .none, .recommendationList:
            errorMessage = "该AI结果不能直接应用"
            return false
        }

        pendingAIResults.removeAll { $0.id == result.id }
        return true
    }

    private func hasSamePendingScope(_ lhs: AIActionResult, as rhs: AIActionResult) -> Bool {
        lhs.applicationTarget == rhs.applicationTarget && lhs.sourceEntityId == rhs.sourceEntityId
    }

    private func diaryEntry(for result: AIActionResult) -> DiaryEntry? {
        guard let sourceEntityId = result.sourceEntityId else {
            return currentEntry
        }

        if currentEntry?.id == sourceEntityId {
            return currentEntry
        }

        return diaryEntries.first { $0.id == sourceEntityId }
    }

    private func transcriptionValidationText(for result: AIActionResult, currentEditorContent: String?) -> String {
        if result.inputSource == .editorContent, let currentEditorContent {
            return currentEditorContent
        }

        return transcribedText
    }

    private func analyzeAcceptedRefinedContent(_ content: String) {
        if let refinedContentAnalysisHandler {
            refinedContentAnalysisHandler(content)
        } else {
            analyzeRefinedContent(content)
        }
    }

    private func recordAIActionFailure(
        actionType: AIActionResult.ActionType,
        applicationTarget: AIActionResult.ApplicationTarget,
        sourceEntityId: UUID? = nil,
        inputSource: AIActionResult.InputSource = .defaultText,
        input: String,
        message: String
    ) {
        errorMessage = message
        recordAIActionResult(.failure(
            actionType: actionType,
            applicationTarget: applicationTarget,
            sourceEntityId: sourceEntityId,
            inputSource: inputSource,
            input: input,
            message: message
        ))
    }
    
    func generateAISummary() {
        guard let entry = currentEntry, !entry.content.isEmpty else {
            errorMessage = "无法生成摘要：日记内容为空"
            return
        }
        let sourceEntryId = entry.id
        let summaryInput = entry.content
        
        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            recordAIActionFailure(
                actionType: .summary,
                applicationTarget: .diarySummary,
                sourceEntityId: sourceEntryId,
                input: summaryInput,
                message: "请在设置中添加DeepSeek API密钥后再使用AI功能"
            )
            return
        }
        
        isProcessingAI = true
        
        openAIService.generateSummary(from: summaryInput)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessingAI = false
                    if case .failure(let error) = completion {
                        self?.recordAIActionFailure(
                            actionType: .summary,
                            applicationTarget: .diarySummary,
                            sourceEntityId: sourceEntryId,
                            input: summaryInput,
                            message: "生成摘要失败: \(error.localizedDescription)"
                        )
                    }
                },
                receiveValue: { [weak self] summary in
                    guard let self = self else { return }
                    self.recordAIActionResult(.success(
                        actionType: .summary,
                        applicationTarget: .diarySummary,
                        sourceEntityId: sourceEntryId,
                        input: summaryInput,
                        outputText: summary
                    ))
                }
            )
            .store(in: &cancellables)
    }
    
    // 使用AI润色语音识别的文本
    func refineTranscribedText(_ text: String, inputSource: AIActionResult.InputSource? = nil) {
        let resolvedInputSource = inputSource ?? transcriptionInputSource

        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            recordAIActionFailure(
                actionType: .refine,
                applicationTarget: .transcriptionText,
                inputSource: resolvedInputSource,
                input: text,
                message: "请在设置中添加DeepSeek API密钥后再使用AI功能"
            )
            return
        }
        
        isProcessingAI = true
        
        openAIService.refineTranscription(text: text)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessingAI = false
                    if case .failure(let error) = completion {
                        self?.recordAIActionFailure(
                            actionType: .refine,
                            applicationTarget: .transcriptionText,
                            inputSource: resolvedInputSource,
                            input: text,
                            message: "优化文本失败: \(error.localizedDescription)"
                        )
                    }
                },
                receiveValue: { [weak self] refinedText in
                    guard let self = self else { return }
                    
                    // 清理可能的多余内容
                    let cleanedText = refinedText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "^[\"']", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "[\"']$", with: "", options: .regularExpression)
                    
                    self.recordAIActionResult(.success(
                        actionType: .refine,
                        applicationTarget: .transcriptionText,
                        inputSource: resolvedInputSource,
                        input: text,
                        outputText: cleanedText
                    ))
                }
            )
            .store(in: &cancellables)
    }
    
    // 分析润色后的内容获取心情和标签建议
    func analyzeRefinedContent(_ content: String) {
        guard !content.isEmpty else { return }
        
        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            recordAIActionFailure(
                actionType: .analyze,
                applicationTarget: .none,
                input: content,
                message: "请在设置中添加DeepSeek API密钥后再使用AI功能"
            )
            return
        }
        
        isProcessingAI = true
        
        // 添加当前日期信息到内容中
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日 EEEE"
        dateFormatter.locale = Locale(identifier: "zh_CN")
        let currentDateStr = dateFormatter.string(from: Date())
        
        let contentWithDate = "日期: \(currentDateStr)\n\n\(content)"
        
        openAIService.analyzeDiaryContent(text: contentWithDate)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessingAI = false
                    if case .failure(let error) = completion {
                        self?.recordAIActionFailure(
                            actionType: .analyze,
                            applicationTarget: .none,
                            input: content,
                            message: "分析日记内容失败: \(error.localizedDescription)"
                        )
                    }
                },
                receiveValue: { [weak self] result in
                    guard let self else { return }
                    self.isProcessingAI = false
                    self.recordAIActionResult(.success(
                        actionType: .analyze,
                        applicationTarget: .none,
                        input: content,
                        outputText: "心情：\(result.moods.joined(separator: "、"))\n标签：\(result.tags.joined(separator: "、"))"
                    ))
                    
                    // 发送通知以更新UI
                    NotificationCenter.default.post(
                        name: Notification.Name("ContentAnalysisCompleted"),
                        object: nil,
                        userInfo: ["moods": result.moods, "tags": result.tags]
                    )
                }
            )
            .store(in: &cancellables)
    }
    
    @discardableResult
    func deleteEntry(_ entry: DiaryEntry) -> Bool {
        let audioURL = entry.audioURL
        modelContext.delete(entry)
        guard saveContext() else {
            return false
        }

        Self.removeRecordingFile(at: audioURL)

        if let index = diaryEntries.firstIndex(where: { $0.id == entry.id }) {
            diaryEntries.remove(at: index)
        }
        
        if currentEntry?.id == entry.id {
            currentEntry = nil
        }

        return true
    }
    
    private func loadDiaryEntries() {
        do {
            let descriptor = FetchDescriptor<DiaryEntry>()
            diaryEntries = try modelContext.fetch(descriptor)
                .sorted { $0.creationDate > $1.creationDate }
        } catch {
            errorMessage = "加载日记失败: \(error.localizedDescription)"
        }
    }
    
    @discardableResult
    private func saveContext(onFailure: (() -> Void)? = nil) -> Bool {
        do {
            try saveModelContext(modelContext)
            errorMessage = nil
            return true
        } catch {
            onFailure?()
            modelContext.rollback()
            errorMessage = "保存日记失败: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - 同步功能
    
    func syncWithCloud() {
        // 在预览环境中不执行同步操作
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            Self.logger.debug("Skipped diary cloud sync in preview")
            return
        }
        
        cloudKitService.syncDiaryEntries(entries: diaryEntries)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "同步失败: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.fetchFromCloud()
                }
            )
            .store(in: &cancellables)
    }
    
    func fetchFromCloud() {
        // 在预览环境中不执行拉取操作
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            Self.logger.debug("Skipped diary cloud fetch in preview")
            return
        }
        
        cloudKitService.fetchDiaryEntries()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "从云端获取数据失败: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] entries in
                    guard let self = self else { return }
                    
                    // 合并云端和本地数据
                    for cloudEntry in entries {
                        if let localIndex = self.diaryEntries.firstIndex(where: { $0.id == cloudEntry.id }) {
                            // 更新现有条目
                            let localEntry = self.diaryEntries[localIndex]
                            
                            // 根据需要更新字段
                            if localEntry.content != cloudEntry.content {
                                localEntry.content = cloudEntry.content
                            }
                            
                            if localEntry.aiSummary != cloudEntry.aiSummary {
                                localEntry.aiSummary = cloudEntry.aiSummary
                            }
                            
                            if localEntry.mood != cloudEntry.mood {
                                localEntry.mood = cloudEntry.mood
                            }
                            
                            if localEntry.tags != cloudEntry.tags {
                                localEntry.tags = cloudEntry.tags
                            }
                            
                            if localEntry.audioURL != cloudEntry.audioURL {
                                localEntry.audioURL = cloudEntry.audioURL
                            }
                        } else {
                            // 添加新条目
                            self.modelContext.insert(cloudEntry)
                            self.diaryEntries.append(cloudEntry)
                        }
                    }
                    
                    // 保存更改
                    _ = self.saveContext()
                }
            )
            .store(in: &cancellables)
        }
    
    private func loadLastSyncDate() {
        // Implementation of loadLastSyncDate method
    }
    
    // MARK: - 模型上下文管理
    
    // 添加一个属性访问器，便于外部检查是否设置了modelContext
    var _modelContext: ModelContext? {
        return modelContext
    }
    
    // 更新模型上下文
    func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
        // 重新加载数据
        loadEntries()
    }
    
    // MARK: - 日记条目管理
    
    // 加载所有日记条目
    func loadEntries() {
        do {
            let descriptor = FetchDescriptor<DiaryEntry>()
            diaryEntries = try modelContext.fetch(descriptor)
                .sorted { $0.creationDate > $1.creationDate }
        } catch {
            Self.logger.error("Failed to load diary entries")
            errorMessage = "加载日记条目失败: \(error.localizedDescription)"
        }
    }
    
    // 为DiaryListView添加所需属性和方法
    var entries: [DiaryEntry] {
        return diaryQuery.apply(to: diaryEntries)
    }
    
    var allEntries: [DiaryEntry] {
        return diaryEntries
    }
    
    // 搜索日记条目
    func searchEntries(_ query: String) {
        updateDiaryQuery { $0.searchText = query }
    }
    
    // 按标签筛选
    func filterByTag(_ tag: String?) {
        updateDiaryQuery { $0.selectedTag = tag }
    }
    
    func filterByMood(_ mood: String?) {
        updateDiaryQuery { $0.selectedMood = mood }
    }

    func setFavoriteOnly(_ favoriteOnly: Bool) {
        updateDiaryQuery { $0.favoriteOnly = favoriteOnly }
    }

    func setDateRange(start: Date?, end: Date?) {
        updateDiaryQuery {
            $0.startDate = start
            $0.endDate = end
        }
    }

    func sortEntries(by option: DiaryEntryQuery.SortOption) {
        updateDiaryQuery { $0.sortOption = option }
    }

    func resetDiaryQuery() {
        diaryQuery = DiaryEntryQuery()
    }

    private func updateDiaryQuery(_ update: (inout DiaryEntryQuery) -> Void) {
        var nextQuery = diaryQuery
        update(&nextQuery)
        diaryQuery = nextQuery
    }
    
    // 收藏/取消收藏日记
    @discardableResult
    func toggleFavorite(_ entry: DiaryEntry) -> Bool {
        entry.isFavorite.toggle()
        entry.lastModified = Date()
        return saveContext()
    }
    
    // 刷新数据
    func refreshData() async {
        // 实现真实的刷新逻辑
        await MainActor.run {
            loadEntries()
        }
    }
    
    // 为TranscriptionDisplayView添加所需方法
    func expandTranscribedText(_ text: String, inputSource: AIActionResult.InputSource? = nil) {
        let resolvedInputSource = inputSource ?? transcriptionInputSource

        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            recordAIActionFailure(
                actionType: .expand,
                applicationTarget: .transcriptionText,
                inputSource: resolvedInputSource,
                input: text,
                message: "请在设置中添加DeepSeek API密钥后再使用AI功能"
            )
            return
        }
        
        isProcessingAI = true
        
        // 实现扩展文本的逻辑
        openAIService.expandText(text: text)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessingAI = false
                    if case .failure(let error) = completion {
                        self?.recordAIActionFailure(
                            actionType: .expand,
                            applicationTarget: .transcriptionText,
                            inputSource: resolvedInputSource,
                            input: text,
                            message: "扩展文本失败: \(error.localizedDescription)"
                        )
                    }
                },
                receiveValue: { [weak self] expandedText in
                    guard let self = self else { return }
                    self.recordAIActionResult(.success(
                        actionType: .expand,
                        applicationTarget: .transcriptionText,
                        inputSource: resolvedInputSource,
                        input: text,
                        outputText: expandedText
                    ))
                }
            )
            .store(in: &cancellables)
    }
    
    // 总结转写文本
    func summarizeTranscribedText(_ text: String, inputSource: AIActionResult.InputSource? = nil) {
        let resolvedInputSource = inputSource ?? transcriptionInputSource

        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            recordAIActionFailure(
                actionType: .summary,
                applicationTarget: .transcriptionText,
                inputSource: resolvedInputSource,
                input: text,
                message: "请在设置中添加DeepSeek API密钥后再使用AI功能"
            )
            return
        }
        
        isProcessingAI = true
        
        // 实现总结文本的逻辑
        openAIService.summarizeText(text: text)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessingAI = false
                    if case .failure(let error) = completion {
                        self?.recordAIActionFailure(
                            actionType: .summary,
                            applicationTarget: .transcriptionText,
                            inputSource: resolvedInputSource,
                            input: text,
                            message: "总结文本失败: \(error.localizedDescription)"
                        )
                    }
                },
                receiveValue: { [weak self] summarizedText in
                    guard let self = self else { return }
                    self.recordAIActionResult(.success(
                        actionType: .summary,
                        applicationTarget: .transcriptionText,
                        inputSource: resolvedInputSource,
                        input: text,
                        outputText: summarizedText
                    ))
                }
            )
            .store(in: &cancellables)
    }
    
    // 创建新日记条目的完整方法
    func createNewEntry(
        title: String,
        content: String,
        mood: String?,
        tags: [String],
        creationDate: Date = Date(),
        audioURL: URL? = nil
    ) -> DiaryEntry? {
        let newEntry = DiaryEntry(title: title)
        newEntry.content = content
        newEntry.mood = mood
        newEntry.tags = tags
        newEntry.creationDate = creationDate
        newEntry.lastModified = creationDate
        newEntry.audioURL = audioURL
        
        modelContext.insert(newEntry)
        guard saveContext() else {
            return nil
        }

        diaryEntries.insert(newEntry, at: 0)
        
        return newEntry
    }
    
    // 添加showToast方法以显示提示消息
    func showToast(message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.showToast = false
        }
    }
}
