import SwiftUI
import AVFoundation
import SwiftData
import UIKit

private enum DiaryEditAlert: Identifiable {
    case discardChanges
    case saveFailure(String)

    var id: String {
        switch self {
        case .discardChanges: "discardChanges"
        case .saveFailure: "saveFailure"
        }
    }
}

struct DiaryEditView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let entry: DiaryEntry
    
    @State private var draft: DiaryEditDraft
    @State private var showingMoodPicker = false
    @State private var showingTagEditor = false
    @State private var isShowingTranscription = false
    @State private var activeAlert: DiaryEditAlert?
    @State private var didResolveDraft = false
    @State private var tempMood: Int
    
    init(viewModel: DiaryViewModel, entry: DiaryEntry) {
        self.viewModel = viewModel
        self.entry = entry
        self._draft = State(initialValue: DiaryEditDraft(
            entryID: entry.id,
            content: entry.content,
            mood: entry.mood,
            tags: entry.tags,
            originalAudioURL: entry.audioURL
        ))
        self._tempMood = State(initialValue: MoodCatalog.index(forStoredLabel: entry.mood) ?? MoodCatalog.defaultIndex)
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
                            content: draft.content,
                            onApplyTranscription: { mode in
                                let nextContent = viewModel.applyTranscription(to: draft.content, mode: mode)
                                guard nextContent != draft.content else { return }
                                draft.content = nextContent
                            }
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
                    if draft.hasChanges || viewModel.isRecording {
                        activeAlert = .discardChanges
                    } else {
                        discardAndDismiss()
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
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .discardChanges:
                Alert(
                    title: Text("放弃更改"),
                    message: Text("您有未保存的更改，确定要放弃吗？"),
                    primaryButton: .destructive(Text("放弃"), action: discardAndDismiss),
                    secondaryButton: .cancel(Text("继续编辑"))
                )
            case .saveFailure(let message):
                Alert(
                    title: Text("保存失败"),
                    message: Text(message),
                    dismissButton: .default(Text("继续编辑"))
                )
            }
        }
        .interactiveDismissDisabled(draft.hasChanges || viewModel.isRecording)
        .onAppear {
            setupOnAppear()
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
                    captureActiveVoiceRecordingIfNeeded()
                    isShowingTranscription = true
                } else {
                    if !viewModel.startRecording() {
                        isShowingTranscription = true
                    }
                }
            } label: {
                Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundColor(viewModel.isRecording ? .red : .blue)
                    .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isRecording)
            }
            
            if !draft.content.isEmpty && !viewModel.isRecording && !viewModel.isProcessingAI {
                Button {
                    viewModel.setTranscriptionText(draft.content, inputSource: .editorContent)
                    viewModel.refineTranscribedText(draft.content, inputSource: .editorContent)
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
                        if let mood = draft.mood {
                            Label(mood, systemImage: MoodCatalog.systemImage(forStoredLabel: mood))
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
                        if draft.tags.isEmpty {
                            Label("添加标签", systemImage: "tag")
                                .foregroundColor(.secondary)
                        } else {
                            Label("\(draft.tags.count)个标签", systemImage: "tag")
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
            if !draft.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.tags, id: \.self) { tag in
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
                if draft.content.isEmpty {
                    Text("写下您的想法...")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.top, 7)
                        .padding(.leading, 5)  // 与"日记内容"标签左对齐
                        .padding(.bottom, 0)
                }
                
                TextEditor(text: $draft.content)
                    .font(.body)
                    .frame(minHeight: 200)
                    .padding(0)
                    .background(Color.clear)
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
        MoodPickerView(selectedMood: Binding(
            get: { tempMood },
            set: { selectedMood in
                tempMood = selectedMood
                draft.mood = MoodCatalog.storedLabel(for: selectedMood)
            }
        ))
            .onDisappear {
                showingMoodPicker = false
            }
    }
    
    private var tagEditorSheet: some View {
        TagEditorView(tags: draft.tags) { updatedTags in
            draft.tags = updatedTags
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
            
            MarkdownView(draft.content)
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
    
    private func insertMarkdownFormat(_ format: String) {
        // 创建一个NSRange来存储当前光标位置
        let cursorPosition = NSRange(location: draft.content.count, length: 0)
        
        // 根据不同的格式类型处理
        switch format {
        case "**粗体**":
            // 在当前位置插入两个星号，然后插入光标，然后再插入两个星号
            let currentPosition = draft.content.count
            draft.content.insert(contentsOf: "**", at: draft.content.index(draft.content.startIndex, offsetBy: currentPosition))
            draft.content.insert(contentsOf: "**", at: draft.content.index(draft.content.startIndex, offsetBy: currentPosition + 2))
            
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
            let currentPosition = draft.content.count
            draft.content.insert(contentsOf: "*", at: draft.content.index(draft.content.startIndex, offsetBy: currentPosition))
            draft.content.insert(contentsOf: "*", at: draft.content.index(draft.content.startIndex, offsetBy: currentPosition + 1))
            
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
            if !draft.content.isEmpty && !draft.content.hasSuffix("\n") {
                draft.content += "\n"
            }
            draft.content += format + " "
        case "- 列表", "1. 编号":
            // 确保列表项在新行上
            if !draft.content.isEmpty && !draft.content.hasSuffix("\n") {
                draft.content += "\n"
            }
            draft.content += format + " "
        default:
            // 默认行为，直接添加格式
            draft.content += format
        }
    }
    
    private func setupOnAppear() {
        // 设置当前条目为正在编辑的条目
        if viewModel.currentEntry?.id != entry.id {
            viewModel.currentEntry = entry
        }
    }
    
    private func cleanupOnDisappear() {
        guard !didResolveDraft else { return }
        captureActiveVoiceRecordingIfNeeded()
        discardPendingRecording()
        clearTransientEditorState()
        didResolveDraft = true
    }
    
    private func saveAndDismiss() {
        captureActiveVoiceRecordingIfNeeded()

        if draft.hasChanges,
           !viewModel.commitEditDraft(draft, forEntryID: entry.id) {
            activeAlert = .saveFailure(viewModel.errorMessage ?? "保存日记失败，请重试")
            return
        }

        clearTransientEditorState()
        didResolveDraft = true
        dismiss()
    }

    private func discardAndDismiss() {
        captureActiveVoiceRecordingIfNeeded()
        discardPendingRecording()
        clearTransientEditorState()
        didResolveDraft = true
        dismiss()
    }

    private func captureActiveVoiceRecordingIfNeeded() {
        guard DiaryViewModel.shouldCaptureVoiceRecordingDraft(
            isRecording: viewModel.isRecording,
            recordingState: viewModel.recordingState
        ) else {
            return
        }

        if viewModel.isRecording {
            viewModel.stopRecording()
        }

        let recording = viewModel.captureVoiceRecordingDraft()
        guard let audioURL = recording.audioURL else { return }

        let supersededRecording = draft.replacePendingRecording(with: audioURL)
        viewModel.discardRecordingFile(at: supersededRecording)
    }

    private func discardPendingRecording() {
        let pendingRecording = draft.discardPendingRecording()
        viewModel.discardRecordingFile(at: pendingRecording)
    }

    private func clearTransientEditorState() {
        viewModel.setTranscriptionText("")
        isShowingTranscription = false
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
