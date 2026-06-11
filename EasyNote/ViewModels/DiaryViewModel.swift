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

class DiaryViewModel: ObservableObject {
    // 服务
    private let speechService = SpeechRecognitionService()
    private let openAIService: OpenAIService
    private let cloudKitService: CloudKitService
    
    // 数据状态
    @Published var diaryEntries: [DiaryEntry] = []
    @Published var currentEntry: DiaryEntry?
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var recordingState: RecordingState = .idle
    @Published var isProcessingAI = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var showToast = false
    @Published var diaryQuery = DiaryEntryQuery()
    
    // 取消令牌
    private var cancellables = Set<AnyCancellable>()
    
    // 模型上下文
    private var modelContext: ModelContext
    
    // MARK: - 初始化方法
    
    init(modelContext: ModelContext?) {
        if let context = modelContext {
            self.modelContext = context
        } else {
            // 如果没有提供ModelContext，创建一个内存中的临时ModelContext
            do {
                let container = try ModelContainer(for: DiaryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                self.modelContext = ModelContext(container)
            } catch {
                // 如果创建失败，创建一个临时的上下文（这在实际情况下可能会导致应用不稳定）
                print("无法创建临时ModelContext: \(error)")
                fatalError("无法创建ModelContext，应用程序无法继续: \(error)")
            }
        }
        
        // 检查是否在预览环境中运行
        let isPreviewEnvironment = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        
        // 在预览环境中使用轻量级服务
        if isPreviewEnvironment {
            self.openAIService = OpenAIService()
            self.cloudKitService = CloudKitService()
            
            // 在预览中不绑定服务状态，避免不必要的处理
            print("DiaryViewModel: 在预览环境中使用轻量级服务")
        } else {
            // 正常环境中的完整初始化
            self.openAIService = OpenAIService()
            self.cloudKitService = CloudKitService()
            
            // 绑定语音服务状态
            speechService.$transcribedText
                .assign(to: &$transcribedText)
            
            speechService.$recordingState
                .assign(to: &$recordingState)
            
            speechService.$isRecording
                .assign(to: &$isRecording)
            
            // 绑定AI处理状态
            openAIService.$isProcessing
                .assign(to: &$isProcessingAI)
            
            // 通过NotificationCenter观察CloudKitService的同步状态变化
            NotificationCenter.default.publisher(for: Notification.Name("CloudKitSyncStatusChanged"))
                .compactMap { $0.object as? Bool }
                .receive(on: RunLoop.main)
                .sink { [weak self] isSyncing in
                    self?.isSyncing = isSyncing
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
        print("检查模型迁移")
    }
    
    // MARK: - 语音录制功能
    
    func startRecording() {
        do {
            try speechService.startRecording()
        } catch {
            // 处理任何可能从语音服务抛出的错误
            self.errorMessage = "录音启动失败: \(error.localizedDescription)"
            self.showToast(message: "录音启动失败，请检查权限设置")
        }
    }
    
    func stopRecording() {
        do {
            try speechService.stopRecording()
        } catch {
            self.errorMessage = "停止录音失败: \(error.localizedDescription)"
        }
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
    func saveVoiceRecordingToCurrentEntry() -> Bool {
        guard let entry = currentEntry else {
            errorMessage = "没有正在编辑的日记"
            return false
        }
        
        let (audioURL, transcription) = speechService.saveRecordingWithTranscription()
        
        if let url = audioURL, FileManager.default.fileExists(atPath: url.path) {
            entry.audioURL = url
            print("成功保存录音到: \(url.path)")
        } else if audioURL != nil {
            print("音频文件URL无效或文件不存在")
        }
        
        // 保存原始识别文本到transcribedText，而不是直接修改entry.content
        if !transcription.isEmpty {
            // 将识别文本保存到transcribedText供用户预览
            self.transcribedText = transcription
            
            // 不再自动润色文本，由用户手动触发
            // if !transcription.isEmpty && !openAIService.apiKey.isEmpty {
            //     refineTranscribedText(transcription)
            // }
        }
        
        // 保存上下文
        return saveContext()
    }
    
    // MARK: - AI功能
    
    // 获取OpenAIService实例
    func getOpenAIService() -> OpenAIService {
        return openAIService
    }
    
    func generateAISummary() {
        guard let entry = currentEntry, !entry.content.isEmpty else {
            errorMessage = "无法生成摘要：日记内容为空"
            return
        }
        
        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            errorMessage = "请在设置中添加DeepSeek API密钥后再使用AI功能"
            return
        }
        
        isProcessingAI = true
        
        openAIService.generateSummary(from: entry.content)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessingAI = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "生成摘要失败: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] summary in
                    guard let self = self, let entry = self.currentEntry else { return }
                    entry.aiSummary = summary
                    entry.lastModified = Date()
                    _ = self.saveContext()
                }
            )
            .store(in: &cancellables)
    }
    
    // 使用AI润色语音识别的文本
    func refineTranscribedText(_ text: String) {
        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            errorMessage = "请在设置中添加DeepSeek API密钥后再使用AI功能"
            return
        }
        
        isProcessingAI = true
        
        openAIService.refineTranscription(text: text)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessingAI = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "优化文本失败: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] refinedText in
                    guard let self = self else { return }
                    
                    // 清理可能的多余内容
                    let cleanedText = refinedText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "^[\"']", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "[\"']$", with: "", options: .regularExpression)
                    
                    // 只更新视图模型的转录文本，不直接修改条目内容
                    self.transcribedText = cleanedText
                    self.isProcessingAI = false
                    
                    // AI润色完成后，分析内容获取心情和标签建议
                    self.analyzeRefinedContent(cleanedText)
                }
            )
            .store(in: &cancellables)
    }
    
    // 分析润色后的内容获取心情和标签建议
    func analyzeRefinedContent(_ content: String) {
        guard !content.isEmpty else { return }
        
        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            errorMessage = "请在设置中添加DeepSeek API密钥后再使用AI功能"
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
                        print("分析日记内容失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] result in
                    self?.isProcessingAI = false
                    
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
        modelContext.delete(entry)
        guard saveContext() else {
            return false
        }

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
            let descriptor = FetchDescriptor<DiaryEntry>(sortBy: [SortDescriptor(\.creationDate, order: .reverse)])
            diaryEntries = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "加载日记失败: \(error.localizedDescription)"
        }
    }
    
    @discardableResult
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            errorMessage = nil
            return true
        } catch {
            modelContext.rollback()
            errorMessage = "保存日记失败: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - 同步功能
    
    func syncWithCloud() {
        // 在预览环境中不执行同步操作
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("DiaryViewModel: 预览环境不执行syncWithCloud")
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
            print("DiaryViewModel: 预览环境不执行fetchFromCloud")
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
            let descriptor = FetchDescriptor<DiaryEntry>(sortBy: [SortDescriptor(\.creationDate, order: .reverse)])
            diaryEntries = try modelContext.fetch(descriptor)
        } catch {
            print("加载日记条目时出错: \(error)")
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
        diaryQuery.searchText = query
    }
    
    // 按标签筛选
    func filterByTag(_ tag: String?) {
        diaryQuery.selectedTag = tag
    }
    
    func filterByMood(_ mood: String?) {
        diaryQuery.selectedMood = mood
    }

    func setFavoriteOnly(_ favoriteOnly: Bool) {
        diaryQuery.favoriteOnly = favoriteOnly
    }

    func setDateRange(start: Date?, end: Date?) {
        diaryQuery.startDate = start
        diaryQuery.endDate = end
    }

    func sortEntries(by option: DiaryEntryQuery.SortOption) {
        diaryQuery.sortOption = option
    }

    func resetDiaryQuery() {
        diaryQuery = DiaryEntryQuery()
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
    func expandTranscribedText(_ text: String) {
        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            errorMessage = "请在设置中添加DeepSeek API密钥后再使用AI功能"
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
                        self?.errorMessage = "扩展文本失败: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] expandedText in
                    guard let self = self else { return }
                    self.transcribedText = expandedText
                }
            )
            .store(in: &cancellables)
    }
    
    // 总结转写文本
    func summarizeTranscribedText(_ text: String) {
        // 验证API密钥是否已设置
        guard !openAIService.apiKey.isEmpty else {
            errorMessage = "请在设置中添加DeepSeek API密钥后再使用AI功能"
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
                        self?.errorMessage = "总结文本失败: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] summarizedText in
                    guard let self = self else { return }
                    self.transcribedText = summarizedText
                }
            )
            .store(in: &cancellables)
    }
    
    // 创建新日记条目的完整方法
    func createNewEntry(title: String, content: String, mood: String?, tags: [String], creationDate: Date = Date()) -> DiaryEntry? {
        let newEntry = DiaryEntry(title: title)
        newEntry.content = content
        newEntry.mood = mood
        newEntry.tags = tags
        newEntry.creationDate = creationDate
        newEntry.lastModified = creationDate
        
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
