//
//  NewDiaryView.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import SwiftUI
import AVFoundation
import SwiftData
import Combine
import UIKit

struct NewDiaryView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    
    // 用于存储取消令牌的本地变量 - 使用@State使其可变
    @State private var cancellables = Set<AnyCancellable>()
    
    // 状态变量
    @State private var title = ""
    @State private var content = ""
    @State private var selectedMood: Int = 3
    @State private var tags: [String] = []
    @State private var showingMoodPicker = false
    @State private var showingTagEditor = false
    @State private var showingImagePicker = false
    @State private var showingDatePicker = false
    @State private var selectedImage: UIImage? = nil
    @State private var selectedDate = Date()
    @State private var isPreviewMode = false
    @State private var isShowingTranscription = false
    @State private var pendingVoiceRecordingAudioURL: URL?
    @State private var didSaveEntry = false
    
    // 录音相关状态
    @State private var contentSaveWorkItem: DispatchWorkItem?
    
    // 初始化方法
    init(viewModel: DiaryViewModel? = nil) {
        // 如果提供了viewModel就使用它，否则创建一个临时的空对象
        if let vm = viewModel {
            self._viewModel = StateObject(wrappedValue: vm)
        } else {
            // 创建ModelContainer和ModelContext可能会抛出异常，使用do-catch处理
            do {
                let container = try ModelContainer(for: DiaryEntry.self)
                let context = ModelContext(container)
                self._viewModel = StateObject(wrappedValue: DiaryViewModel(modelContext: context))
            } catch {
                // 发生错误时打印错误并使用一个简单的空ModelContext
                print("创建ModelContainer失败: \(error.localizedDescription)")
                
                // 使用内存中的配置创建一个临时容器
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    let tempContainer = try ModelContainer(for: DiaryEntry.self, configurations: config)
                    let tempContext = ModelContext(tempContainer)
                    self._viewModel = StateObject(wrappedValue: DiaryViewModel(modelContext: tempContext))
                } catch {
                    // 如果还是失败，创建一个没有模型上下文的ViewModel
                    print("创建临时ModelContainer也失败: \(error.localizedDescription)")
                    // ViewModel初始化方法已修改为支持nil的ModelContext
                    self._viewModel = StateObject(wrappedValue: DiaryViewModel(modelContext: nil))
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 拆分为更小的子视图
                    titleInputSection
                    
                    // 心情和标签区域
                    moodAndTagsSection
                    
                    // 当前标签显示
                    tagsDisplaySection
                    
                    // 内容润色按钮
                    contentRefinementButton
                    
                    Divider()
                    
                    // 转写结果显示
                    transcriptionSection
                    
                    // 内容编辑
                    contentEditSection
                }
                .padding()
                .sheet(isPresented: $showingMoodPicker) {
                    MoodPickerSheet()
                }
                .sheet(isPresented: $showingTagEditor) {
                    TagEditorSheet()
                }
                .sheet(isPresented: $showingDatePicker) {
                    DatePickerSheet()
                }
                .navigationTitle("创建新日记")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            saveEntry()
                        }
                        .disabled(title.isEmpty)
                    }
                }
            }
        }
        .onDisappear {
            cleanupDraftRecordingIfNeeded()
            viewModel.transcribedText = ""
        }
    }
    
    // MARK: - 子视图
    
    // 标题输入区域
    private var titleInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日记标题")
                .font(.headline)
            
            TextField("请输入标题...", text: $title)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    // 心情和标签编辑区
    private var moodAndTagsSection: some View {
        HStack(spacing: 12) {
            moodButton
            tagButton
            Spacer()
            recordingButton
        }
    }
    
    // 心情选择按钮
    private var moodButton: some View {
        Button {
            showingMoodPicker = true
        } label: {
            HStack {
                Text(moodText(for: selectedMood))
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(16)
        }
    }
    
    // 返回心情文本描述
    private func moodText(for mood: Int) -> String {
        switch mood {
        case 1: return "很糟 😢"
        case 2: return "不好 😔"
        case 3: return "一般 😐"
        case 4: return "不错 😊"
        case 5: return "很棒 😁"
        case 6: return "愤怒 😡"
        case 7: return "恐惧 😱"
        case 8: return "焦虑 😨"
        case 9: return "思考 🤔"
        case 10: return "疲倦 😴"
        case 11: return "兴奋 🥳"
        case 12: return "搞笑 😂"
        case 13: return "爱意 🥰"
        case 14: return "感恩 😇"
        case 15: return "自信 😎"
        case 16: return "放松 😌"
        default: return "一般 😐"
        }
    }
    
    // 将Int类型的mood转换为String?类型
    private func moodStringValue(for mood: Int) -> String? {
        switch mood {
        case 1: return "很糟"
        case 2: return "不好"
        case 3: return "一般"
        case 4: return "不错"
        case 5: return "很棒"
        case 6: return "愤怒"
        case 7: return "恐惧"
        case 8: return "焦虑"
        case 9: return "思考"
        case 10: return "疲倦"
        case 11: return "兴奋"
        case 12: return "搞笑"
        case 13: return "爱意"
        case 14: return "感恩"
        case 15: return "自信"
        case 16: return "放松"
        default: return nil
        }
    }
    
    // 标签按钮
    private var tagButton: some View {
        Button {
            showingTagEditor = true
        } label: {
            HStack {
                Text(tags.isEmpty ? "添加标签" : "\(tags.count)个标签")
                    .foregroundColor(tags.isEmpty ? .secondary : .primary)
                Image(systemName: "tag")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(16)
        }
    }
    
    // 录音按钮
    private var recordingButton: some View {
        Button {
            if viewModel.isRecording {
                captureActiveVoiceRecordingIfNeeded()
                isShowingTranscription = true
            } else {
                if !viewModel.startRecording() {
                    isShowingTranscription = true
                }
            }
        } label: {
            HStack {
                Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .foregroundColor(viewModel.isRecording ? .red : .blue)
                    .font(.title2)
                Text(viewModel.isRecording ? "停止" : "语音输入")
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(viewModel.isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
            .cornerRadius(16)
        }
    }
    
    // 标签显示区域
    private var tagsDisplaySection: some View {
        Group {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
    
    // 内容润色按钮
    private var contentRefinementButton: some View {
        Group {
            if !content.isEmpty && !viewModel.isRecording && !viewModel.isProcessingAI {
                Button {
                    viewModel.transcribedText = content
                    viewModel.refineTranscribedText(content)
                    isShowingTranscription = true
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("润色内容")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(16)
                }
            }
        }
    }
    
    // 转写结果显示
    private var transcriptionSection: some View {
        Group {
            if isShowingTranscription || viewModel.isRecording || !viewModel.transcribedText.isEmpty {
                TranscriptionDisplayView(
                    viewModel: viewModel,
                    isShowingTranscription: isShowingTranscription,
                    content: content,
                    onApplyTranscription: { mode in
                        content = viewModel.applyTranscription(to: content, mode: mode)
                    }
                )
            }
        }
    }
    
    // 内容编辑区域
    private var contentEditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日记内容")
                .font(.headline)
            
            if isPreviewMode {
                previewContent
            } else {
                contentEditor
            }
            
            togglePreviewButton
        }
    }
    
    // 预览内容
    private var previewContent: some View {
        ScrollView {
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
        }
        .frame(minHeight: 200)
    }
    
    // 内容编辑器
    private var contentEditor: some View {
        TextEditor(text: $content)
            .frame(minHeight: 200)
            .padding(4)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
    }
    
    // 切换预览模式按钮
    private var togglePreviewButton: some View {
        Button {
            isPreviewMode.toggle()
        } label: {
            Text(isPreviewMode ? "编辑模式" : "预览模式")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
        }
    }
    
    // MARK: - Sheet视图
    
    // 心情选择器Sheet
    private func MoodPickerSheet() -> some View {
        MoodPickerView(selectedMood: $selectedMood)
    }
    
    // 标签编辑器Sheet
    private func TagEditorSheet() -> some View {
        TagEditorView(tags: tags) { updatedTags in
            self.tags = updatedTags
            showingTagEditor = false
        }
    }
    
    // 日期选择器Sheet
    private func DatePickerSheet() -> some View {
        NavigationView {
            VStack {
                DatePicker("选择日期", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .padding()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                
                Spacer()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确定") {
                        showingDatePicker = false
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }
    
    // MARK: - 事件处理方法
    
    // 保存日记条目
    private func saveEntry() {
        captureActiveVoiceRecordingIfNeeded()

        let newEntry = viewModel.createNewEntry(
            title: title,
            content: content,
            mood: moodStringValue(for: selectedMood),
            tags: tags,
            creationDate: selectedDate,
            audioURL: pendingVoiceRecordingAudioURL
        )

        guard newEntry != nil else {
            return
        }

        didSaveEntry = true
        
        dismiss()
    }
    
    // 插入 Markdown 格式
    private func insertMarkdownFormat(_ format: String) {
        switch format {
        case "**粗体**":
            // 在当前位置插入两个星号，然后插入光标，然后再插入两个星号
            content.append("**粗体**")
        case "*斜体*":
            content.append("*斜体*")
        case "# 标题", "## 二级标题":
            // 确保在新行上添加标题
            if !content.isEmpty && !content.hasSuffix("\n") {
                content += "\n"
            }
            content += format + " "
        case "- 列表", "1. 编号":
            // 确保列表项在新行上
            if !content.isEmpty && !content.hasSuffix("\n") {
                content += "\n"
            }
            content += format + " "
        default:
            // 默认行为，直接添加格式
            content += format
        }
    }

    private func captureActiveVoiceRecordingIfNeeded() {
        guard viewModel.isRecording else {
            return
        }

        viewModel.stopRecording()
        let recording = viewModel.captureVoiceRecordingDraft()
        pendingVoiceRecordingAudioURL = recording.audioURL
    }

    private func cleanupDraftRecordingIfNeeded() {
        captureActiveVoiceRecordingIfNeeded()

        if !didSaveEntry {
            viewModel.discardRecordingFile(at: pendingVoiceRecordingAudioURL)
        }

        pendingVoiceRecordingAudioURL = nil
    }
}

// MARK: - 辅助视图

// 移除旧的StepIndicatorView结构体，因为我们不再使用分步骤创建

// MARK: - 预览
#Preview {
    // 使用内存中的配置创建轻量级预览容器
    let viewModel = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: DiaryEntry.self, configurations: config)
            let context = ModelContext(container)
            return DiaryViewModel(modelContext: context)
        } catch {
            // 失败时使用nil modelContext，这应该不会引发致命错误
            print("预览创建失败: \(error)")
            return DiaryViewModel(modelContext: nil)
        }
    }()
    
    return NewDiaryView(viewModel: viewModel)
        .onAppear {
            // 设置一些初始值以便预览
            viewModel.transcribedText = "这是预览中的转录文本示例"
        }
}

// MARK: - DiaryEntry扩展
extension DiaryEntry {
    // 临时存储AI建议的心情和标签
    var suggestedMoods: [String] {
        get { getTemporaryValue(for: &DiaryEntryKeys.suggestedMoods) as? [String] ?? [] }
        set { setTemporaryValue(newValue, for: &DiaryEntryKeys.suggestedMoods) }
    }
    
    var suggestedTags: [String] {
        get { getTemporaryValue(for: &DiaryEntryKeys.suggestedTags) as? [String] ?? [] }
        set { setTemporaryValue(newValue, for: &DiaryEntryKeys.suggestedTags) }
    }
    
    private func getTemporaryValue(for key: UnsafeRawPointer) -> Any? {
        return objc_getAssociatedObject(self, key)
    }
    
    private func setTemporaryValue(_ value: Any, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(self, key, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// 关联对象的键
private struct DiaryEntryKeys {
    static var suggestedMoods: UnsafeRawPointer = UnsafeRawPointer(bitPattern: "DiaryEntry.suggestedMoods".hashValue)!
    static var suggestedTags: UnsafeRawPointer = UnsafeRawPointer(bitPattern: "DiaryEntry.suggestedTags".hashValue)!
}
