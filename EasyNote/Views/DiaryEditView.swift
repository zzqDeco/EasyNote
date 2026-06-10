import SwiftUI
import AVFoundation
import SwiftData
import Combine
import UIKit

struct DiaryEditView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let entry: DiaryEntry
    
    @State private var editedContent: String = ""
    @State private var showingMoodPicker = false
    @State private var showingTagEditor = false
    @State private var isRecording = false
    @State private var contentSaveWorkItem: DispatchWorkItem?
    @State private var isShowingTranscription = false
    @State private var showingCancelAlert = false
    @State private var hasChanges = false
    @State private var tempMood: Int = 1 // 添加临时状态来保存心情值
    
    init(viewModel: DiaryViewModel, entry: DiaryEntry) {
        self.viewModel = viewModel
        self.entry = entry
        self._editedContent = State(initialValue: entry.content)
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 标题显示
                    Text(entry.title)
                        .font(.system(.largeTitle, design: .serif))
                        .fontWeight(.bold)
                        .padding(.bottom, 5)
                    
                    // 日期和工具栏
                    HStack {
                        // 更醒目的日期显示
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                            
                            Text(formattedDate())
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                        
                        Spacer()
                        
                        // 工具栏
                        toolbarView
                    }
                    
                    // 心情和标签编辑区
                    moodAndTagsView
                    
                    Divider()
                        .padding(.vertical, 5)
                    
                    // 转写结果显示 - 使用共享组件
                    if isShowingTranscription || viewModel.isRecording || !viewModel.transcribedText.isEmpty {
                        TranscriptionDisplayView(
                            viewModel: viewModel,
                            isShowingTranscription: isShowingTranscription,
                            content: editedContent
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: isShowingTranscription)
                    }
                    
                    // 内容编辑
                    contentEditorView
                    
                    // 最后一部分内容
                    markdownPreview
                }
                .padding()
                .padding(.bottom, 70) // 添加额外的底部间距，避免与底部菜单重叠
            }
            .background(Color(UIColor.systemBackground))
            
            // 录音指示器悬浮层
            if viewModel.isRecording {
                recordingIndicatorView
            }
            
            // Toast消息
            if viewModel.showToast, let message = viewModel.toastMessage {
                VStack {
                    Spacer()
                    
                    Text(message)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.7))
                        )
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .shadow(radius: 1)
                        .padding(.bottom, 70)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: viewModel.showToast)
                .zIndex(100)
            }
        }
        .navigationTitle("编辑日记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") {
                    saveAndDismiss()
                }
                .fontWeight(.medium)
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    if hasChanges {
                        showingCancelAlert = true
                    } else {
                        dismiss()
                    }
                }
                .foregroundColor(.red)
            }
        }
        .sheet(isPresented: $showingMoodPicker) {
            moodPickerSheet
        }
        .sheet(isPresented: $showingTagEditor) {
            tagEditorSheet
        }
        .alert("放弃更改", isPresented: $showingCancelAlert) {
            Button("放弃", role: .destructive) {
                dismiss()
            }
            Button("继续编辑", role: .cancel) { }
        } message: {
            Text("您有未保存的更改，确定要放弃吗？")
        }
        .onAppear {
            setupOnAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UseTranscribedContent"))) { notification in
            handleTranscribedContent(notification)
        }
        .onDisappear {
            cleanupOnDisappear()
        }
    }
    
    // MARK: - 子视图
    
    private var toolbarView: some View {
        HStack(spacing: 16) {
            Button {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                    viewModel.saveVoiceRecordingToCurrentEntry()
                    isShowingTranscription = true
                } else {
                    viewModel.startRecording()
                }
            } label: {
                Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundColor(viewModel.isRecording ? .red : .blue)
                    .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isRecording)
            }
            
            if !editedContent.isEmpty && !viewModel.isRecording && !viewModel.isProcessingAI {
                Button {
                    viewModel.transcribedText = editedContent
                    viewModel.refineTranscribedText(editedContent)
                    isShowingTranscription = true
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundColor(.purple)
                }
            }
        }
    }
    
    private var moodAndTagsView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    showingMoodPicker = true
                } label: {
                    HStack {
                        if let mood = entry.mood {
                            Label(mood, systemImage: moodIcon(for: mood))
                        } else {
                            Label("选择心情", systemImage: "face.smiling")
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
                
                Button {
                    showingTagEditor = true
                } label: {
                    HStack {
                        if entry.tags.isEmpty {
                            Label("添加标签", systemImage: "tag")
                                .foregroundColor(.secondary)
                        } else {
                            Label("\(entry.tags.count)个标签", systemImage: "tag")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(16)
                }
                
                Spacer()
            }
            
            // 当前标签显示
            if !entry.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }
    
    private var contentEditorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("日记内容")
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
            
            ZStack(alignment: .topLeading) {
                if editedContent.isEmpty {
                    Text("写下您的想法...")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.top, 7)
                        .padding(.leading, 5)  // 与"日记内容"标签左对齐
                        .padding(.bottom, 0)
                }
                
                TextEditor(text: $editedContent)
                    .font(.body)
                    .frame(minHeight: 200)
                    .padding(0)
                    .background(Color.clear)
                    .onChange(of: editedContent) { _, newValue in
                        handleContentChange(newValue)
                    }
            }
            .padding(.horizontal, 5)
            .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
            .cornerRadius(12)
            .shadow(color: Color.primary.opacity(0.1), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            // Markdown工具栏
            markdownToolbar
            
            // Markdown指南
            markdownGuide
        }
    }
    
    private var markdownToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([
                    ("# 标题", "textformat.size.larger"),
                    ("## 二级标题", "textformat.size"),
                    ("**粗体**", "bold"),
                    ("*斜体*", "italic"),
                    ("- 列表", "list.bullet"),
                    ("1. 编号", "list.number")
                ], id: \.0) { format, icon in
                    Button {
                        insertMarkdownFormat(format)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.caption)
                            Text(format)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var markdownGuide: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Markdown快速指南:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text("点击上方按钮插入格式，或直接输入以下格式：")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text("# 大标题, ## 二级标题, **粗体文本**, *斜体文本*, - 无序列表, 1. 有序列表")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
    
    private var recordingIndicatorView: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                    
                    Text("正在录音...")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
                .padding()
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3), value: viewModel.isRecording)
                
                Spacer()
            }
            
            Spacer().frame(height: 100)
        }
    }
    
    private var moodPickerSheet: some View {
        MoodPickerView(selectedMood: $tempMood)
            .onDisappear {
                if tempMood != 1 { // 假设1是默认值
                    viewModel.updateCurrentEntry(mood: String(tempMood))
                }
                showingMoodPicker = false
            }
    }
    
    private var tagEditorSheet: some View {
        TagEditorView(tags: entry.tags) { updatedTags in
            viewModel.updateCurrentEntry(tags: updatedTags)
            showingTagEditor = false
        }
    }
    
    // 添加Markdown预览视图
    private var markdownPreview: some View {
        // Markdown预览区
        VStack(alignment: .leading, spacing: 8) {
            Text("内容预览")
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
                .padding(.top, 8)
            
            MarkdownView(editedContent)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - 辅助方法
    
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: entry.lastModified)
    }
    
    private func moodIcon(for mood: String) -> String {
        switch mood {
        case "很糟": return "cloud.rain"
        case "不好": return "cloud"
        case "一般": return "sun.min"
        case "不错": return "sun.max"
        case "很棒": return "sun.max.fill"
        case "愤怒": return "flame"
        case "恐惧": return "exclamationmark.triangle"
        case "焦虑": return "arrow.up.heart"
        case "思考": return "bubble.left.and.bubble.right"
        case "疲倦": return "moon.zzz"
        case "兴奋": return "star.fill"
        case "搞笑": return "face.smiling"
        case "爱意": return "heart.fill"
        case "感恩": return "hands.sparkles"
        case "自信": return "person.fill.checkmark"
        case "放松": return "leaf"
        // 保留旧的映射以兼容旧数据
        case "开心": return "face.smiling"
        case "平静": return "face.dashed"
        case "伤心": return "face.sad"
        case "生气": return "face.angered"
        case "惊讶": return "face.surprised"
        case "疲惫": return "face.exhausted"
        default: return "sun.min"
        }
    }
    
    private func insertMarkdownFormat(_ format: String) {
        // 创建一个NSRange来存储当前光标位置
        let cursorPosition = NSRange(location: editedContent.count, length: 0)
        
        // 根据不同的格式类型处理
        switch format {
        case "**粗体**":
            // 在当前位置插入两个星号，然后插入光标，然后再插入两个星号
            let currentPosition = editedContent.count
            editedContent.insert(contentsOf: "**", at: editedContent.index(editedContent.startIndex, offsetBy: currentPosition))
            editedContent.insert(contentsOf: "**", at: editedContent.index(editedContent.startIndex, offsetBy: currentPosition + 2))
            
            // 模拟光标移动到中间位置
            DispatchQueue.main.async {
                // 获取UIWindow并查找UITextView
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                let window = windowScene?.windows.first
                
                if let textView = window?.rootViewController?.view.findUITextView() {
                    textView.selectedRange = NSRange(location: cursorPosition.location + 2, length: 0)
                }
            }
        case "*斜体*":
            // 在当前位置插入一个星号，然后插入光标，然后再插入一个星号
            let currentPosition = editedContent.count
            editedContent.insert(contentsOf: "*", at: editedContent.index(editedContent.startIndex, offsetBy: currentPosition))
            editedContent.insert(contentsOf: "*", at: editedContent.index(editedContent.startIndex, offsetBy: currentPosition + 1))
            
            // 模拟光标移动到中间位置
            DispatchQueue.main.async {
                // 获取UIWindow并查找UITextView
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                let window = windowScene?.windows.first
                
                if let textView = window?.rootViewController?.view.findUITextView() {
                    textView.selectedRange = NSRange(location: cursorPosition.location + 1, length: 0)
                }
            }
        case "# 标题", "## 二级标题":
            // 不添加换行，直接插入标题标记
            if !editedContent.isEmpty && !editedContent.hasSuffix("\n") {
                editedContent += "\n"
            }
            editedContent += format + " "
        case "- 列表", "1. 编号":
            // 确保列表项在新行上
            if !editedContent.isEmpty && !editedContent.hasSuffix("\n") {
                editedContent += "\n"
            }
            editedContent += format + " "
        default:
            // 默认行为，直接添加格式
            editedContent += format
        }
        
        // 更新内容
        viewModel.updateCurrentEntry(content: editedContent)
        hasChanges = true
    }
    
    private func handleContentChange(_ newValue: String) {
        // 标记有更改
        hasChanges = true
        
        // 取消之前的延迟保存
        contentSaveWorkItem?.cancel()
        
        // 创建新的延迟保存任务
        let workItem = DispatchWorkItem {
            viewModel.updateCurrentEntry(content: newValue)
        }
        
        // 存储并延迟执行
        contentSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    private func handleTranscribedContent(_ notification: Notification) {
        if let transcribedText = notification.object as? String,
           let isReplacing = notification.userInfo?["replace"] as? Bool {
            if isReplacing {
                // 替换当前内容
                editedContent = transcribedText
            } else {
                // 追加到当前内容
                if !editedContent.isEmpty {
                    editedContent += "\n\n" + transcribedText
                } else {
                    editedContent = transcribedText
                }
            }
            // 更新条目内容
            viewModel.updateCurrentEntry(content: editedContent)
            hasChanges = true
        }
    }
    
    private func setupOnAppear() {
        // 确保编辑内容始终与条目内容同步
        editedContent = entry.content
        
        // 设置当前条目为正在编辑的条目
        if viewModel.currentEntry?.id != entry.id {
            viewModel.currentEntry = entry
        }
        
        // 初始化时重置hasChanges
        hasChanges = false
    }
    
    private func cleanupOnDisappear() {
        // 取消所有延迟的内容保存操作
        contentSaveWorkItem?.cancel()
        contentSaveWorkItem = nil
        
        // 停止录音（如果正在录音）
        if viewModel.isRecording {
            viewModel.stopRecording()
            viewModel.saveVoiceRecordingToCurrentEntry()
        }
    }
    
    private func saveAndDismiss() {
        // 确保所有更改已保存
        if let pendingWorkItem = contentSaveWorkItem, !pendingWorkItem.isCancelled {
            pendingWorkItem.perform()
        }
        
        // 关闭编辑界面
        dismiss()
    }
}

#Preview {
    // 使用预览辅助工具创建一个一致的预览环境
    let viewModel = PreviewHelpers.createViewModel()
    let entry = PreviewHelpers.sampleEntry
    
    DiaryEditView(
        viewModel: viewModel,
        entry: entry
    )
    .environmentObject(PreviewHelpers.tabManager)
    .modelContainer(PreviewHelpers.previewContainer)
} 