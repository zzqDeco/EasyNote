//
//  CreateDiaryView.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import SwiftUI
import AVFoundation
import SwiftData
import Combine
import UIKit
import AVFAudio

struct CreateDiaryView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    
    @State private var title = ""
    @State private var content = ""
    @State private var mood: Int = 3
    @State private var tags: [String] = []
    @State private var isShowingMoodPicker = false
    @State private var isShowingTagEditor = false
    @State private var isRecording = false
    @State private var isShowingTranscription = false
    @State private var pendingVoiceRecordingAudioURL: URL?
    @State private var didSaveEntry = false
    @State private var titleHeightChanged = false
    @State private var selectedDate = Date()
    @State private var isShowingDatePicker = false
    
    // 动画状态
    @State private var showKeyboardToolbar = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var contentFocused = false
    
    // 日期格式器
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题输入区
            titleInputView
            
            Divider()
            
            // 转写显示区域
            transcriptionView
            
            // 内容输入区
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 心情和标签区域
                    moodAndTagsView
                    
                    // 正文编辑区
                    contentInputView
                }
                .padding()
                // 添加足够的底部间距，避免底部工具栏遮挡内容
                .padding(.bottom, 100)
            }
            
            // 底部工具栏
            bottomToolbar
        }
        .background(Color(UIColor.systemBackground))
        .overlay(
            // Toast消息
            Group {
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
        )
        .onAppear {
            setupKeyboardObservers()
            
            // 清空已使用的转写内容，避免重复显示
            viewModel.setTranscriptionText("")
        }
        .onDisappear {
            removeKeyboardObservers()
            cleanupDraftRecordingIfNeeded()
            viewModel.setTranscriptionText("")
        }
        // 监听主题色变化，强制视图刷新
        .id("theme-\(themeManager.accentColor.description)")
        .sheet(isPresented: $isShowingMoodPicker) {
            MoodPickerView(selectedMood: $mood)
        }
        .sheet(isPresented: $isShowingTagEditor) {
            TagEditorView(tags: $tags)
        }
        .sheet(isPresented: $isShowingDatePicker) {
            datePickerSheet
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    isPresented = false
                    dismiss()
                }
                .foregroundColor(.red)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    saveEntry()
                }
                .disabled(title.isEmpty)
                .fontWeight(.medium)
            }
        }
    }
    
    // MARK: - 子视图
    
    private var titleInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题标签和日期显示
            HStack {
                titleLabel
                Spacer()
                dateDisplay
            }
            .padding(.horizontal)
            
            titleEditor
        }
        .padding(.bottom, 10)
    }
    
    private var titleLabel: some View {
        Text("标题")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 16)
    }
    
    // 添加日期显示组件
    private var dateDisplay: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.footnote)
                .foregroundColor(.gray)
            
            Text(dateFormatter.string(from: selectedDate))
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .padding(.top, 16)
    }
    
    private var titleEditor: some View {
        ZStack(alignment: .topLeading) {
            if title.isEmpty {
                Text("给您的日记起个标题...")
                    .font(.title2.bold())
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(.top, 7)
                    .padding(.leading, 12)  // 与"标题"标签左对齐
                    .padding(.bottom, 0)
            }
            
            TextEditor(text: $title)
                .font(.title2.bold())
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(height: titleHeightChanged ? 80 : 45)
                .padding(0)
                .onChange(of: title) { _, newValue in
                    updateTitleHeight(newValue)
                }
        }
        .padding(.horizontal, 12)
    }
    
    private func updateTitleHeight(_ newValue: String) {
        if newValue.contains("\n") {
            title = newValue.replacingOccurrences(of: "\n", with: "")
            withAnimation {
                titleHeightChanged = false
            }
        } else if newValue.count > 30 && !titleHeightChanged {
            withAnimation {
                titleHeightChanged = true
            }
        } else if newValue.count <= 30 && titleHeightChanged {
            withAnimation {
                titleHeightChanged = false
            }
        }
    }
    
    private var transcriptionView: some View {
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
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: isShowingTranscription)
            }
        }
    }
    
    private var moodAndTagsView: some View {
        VStack(spacing: 12) {
            // 重设按钮组
            HStack(spacing: 12) {
                // 心情按钮
                Button {
                    isShowingMoodPicker = true
                } label: {
                    HStack {
                        Image(systemName: moodIcon(for: mood))
                            .foregroundColor(themeManager.accentColor)
                        Text(moodText(for: mood))
                            .foregroundColor(themeManager.accentColor)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(themeManager.accentColor.opacity(0.7))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(themeManager.accentColor.opacity(0.1))
                    .cornerRadius(12)
                    // 添加id确保主题色变化时视图会刷新
                    .id("mood-button-\(themeManager.accentColor.description)")
                }
                
                // 标签按钮
                Button {
                    isShowingTagEditor = true
                } label: {
                    HStack {
                        Image(systemName: "tag")
                            .foregroundColor(.green)
                        Text(tags.isEmpty ? "添加标签" : "\(tags.count)个标签")
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            
            // 当前标签显示
            tagsList
        }
    }
    
    private var tagsList: some View {
        Group {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 8)
            }
        }
    }
    
    private var contentInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题部分
            contentTitleView
            
            // 内容编辑区
            contentEditorView
            
            // Markdown工具栏
            markdownToolbarView
            
            // Markdown指南
            markdownGuideView
        }
    }
    
    // 拆分为子视图组件
    private var contentTitleView: some View {
        Text("日记内容")
            .font(.headline)
            .foregroundColor(.primary.opacity(0.8))
            .padding(.top, 8)
    }
    
    private var contentEditorView: some View {
        ZStack(alignment: .topLeading) {
            if content.isEmpty {
                Text("写下您的想法...")
                    .font(.body)
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(.top, 7)
                    .padding(.leading, 5)  // 与"日记内容"标签左对齐
                    .padding(.bottom, 0)
            }
            
            TextEditor(text: $content)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .background(Color.clear)
                .padding(0)
                .onTapGesture {
                    contentFocused = true
                }
        }
        .padding(.horizontal, 5)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.bottom, 8)
    }
    
    private var markdownToolbarView: some View {
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
                                .foregroundColor(themeManager.accentColor)
                            Text(format)
                                .font(.caption)
                                .foregroundColor(themeManager.accentColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(themeManager.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .id("markdown-\(format)-\(themeManager.accentColor.description)")
                }
            }
        }
        .padding(.bottom, 4)
    }
    
    private var markdownGuideView: some View {
        Text("提示: 使用Markdown格式可以让您的日记更加结构化和美观")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, 20)
    }
    
    private var bottomToolbar: some View {
        HStack {
            // 工具按钮组
            toolButtons
            
            Spacer()
            
            // 右侧分隔线
            Divider()
                .frame(height: 30)
                .padding(.horizontal, 8)
            
            // 保存按钮
            saveButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: -2)
        )
    }
    
    private var toolButtons: some View {
        HStack(spacing: 20) {  // 适当减少间距
            // 语音按钮
            Button {
                handleRecordingAction()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title3)
                        .foregroundColor(viewModel.isRecording ? .red : themeManager.accentColor)
                        .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isRecording)
                    Text(viewModel.isRecording ? "停止" : "语音")
                        .font(.caption2)
                        .foregroundColor(viewModel.isRecording ? .red : themeManager.accentColor)
                }
                .frame(minWidth: 50)
                // 添加id确保主题色变化时视图会刷新
                .id("mic-button-\(themeManager.accentColor.description)")
            }
            
            // AI润色按钮 - 增加标签说明
            Button {
                handleRefinementAction()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                        .foregroundColor(.purple)
                    Text("AI润色")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                .frame(minWidth: 50)
            }
            .disabled(content.isEmpty || viewModel.isRecording || viewModel.isProcessingAI)
            .opacity(content.isEmpty || viewModel.isRecording || viewModel.isProcessingAI ? 0.5 : 1.0)
            
            // 日期选择器按钮
            Button {
                isShowingDatePicker = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text("日期")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(minWidth: 50)
            }
        }
    }
    
    private var saveButton: some View {
        Button {
            saveEntry()
        } label: {
            Text("保存")
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(title.isEmpty ? Color.gray.opacity(0.3) : themeManager.accentColor)
                .foregroundColor(title.isEmpty ? .gray : .white)
                .cornerRadius(8)
                .id("save-button-\(themeManager.accentColor.description)")
        }
        .disabled(title.isEmpty)
    }
    
    // MARK: - 辅助方法
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                self.keyboardHeight = keyboardFrame.height
                withAnimation {
                    self.showKeyboardToolbar = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation {
                self.showKeyboardToolbar = false
                self.keyboardHeight = 0
                self.contentFocused = false
            }
        }
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    private func insertMarkdownFormat(_ format: String) {
        // 根据不同的格式类型处理
        switch format {
        case "**粗体**":
            // 在当前位置插入两个星号，然后插入光标，然后再插入两个星号
            let currentPosition = content.count
            content.insert(contentsOf: "**", at: content.index(content.startIndex, offsetBy: currentPosition))
            content.insert(contentsOf: "**", at: content.index(content.startIndex, offsetBy: currentPosition + 2))
            
            // 模拟光标移动到中间位置
            DispatchQueue.main.async {
                // 获取UIWindow并查找UITextView
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                let window = windowScene?.windows.first
                
                if let textView = window?.rootViewController?.view.findUITextView() {
                    textView.selectedRange = NSRange(location: currentPosition + 2, length: 0)
                }
            }
        case "*斜体*":
            // 在当前位置插入一个星号，然后插入光标，然后再插入一个星号
            let currentPosition = content.count
            content.insert(contentsOf: "*", at: content.index(content.startIndex, offsetBy: currentPosition))
            content.insert(contentsOf: "*", at: content.index(content.startIndex, offsetBy: currentPosition + 1))
            
            // 模拟光标移动到中间位置
            DispatchQueue.main.async {
                // 获取UIWindow并查找UITextView
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                let window = windowScene?.windows.first
                
                if let textView = window?.rootViewController?.view.findUITextView() {
                    textView.selectedRange = NSRange(location: currentPosition + 1, length: 0)
                }
            }
        case "# 标题", "## 二级标题":
            // 不添加换行，直接插入标题标记
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
    
    private func saveEntry() {
        captureActiveVoiceRecordingIfNeeded()

        // 创建新的日记条目，使用选定的日期
        let newEntry = viewModel.createNewEntry(
            title: title,
            content: content,
            mood: moodStringValue(for: mood),
            tags: tags,
            creationDate: selectedDate,
            audioURL: pendingVoiceRecordingAudioURL
        )

        guard newEntry != nil else {
            return
        }

        didSaveEntry = true
        
        // 清空转写文本
        viewModel.setTranscriptionText("")
        
        // 关闭视图
        isPresented = false
        dismiss()
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
    
    private func moodIcon(for mood: Int) -> String {
        switch mood {
        case 1: return "cloud.rain"
        case 2: return "cloud"
        case 3: return "sun.min"
        case 4: return "sun.max"
        case 5: return "sun.max.fill"
        case 6: return "flame"
        case 7: return "exclamationmark.triangle"
        case 8: return "arrow.up.heart"
        case 9: return "bubble.left.and.bubble.right"
        case 10: return "moon.zzz"
        case 11: return "star.fill"
        case 12: return "face.smiling"
        case 13: return "heart.fill"
        case 14: return "hands.sparkles"
        case 15: return "person.fill.checkmark"
        case 16: return "leaf"
        default: return "sun.min"
        }
    }
    
    // 提取功能逻辑到单独的方法中
    private func handleRecordingAction() {
        if viewModel.isRecording {
            captureActiveVoiceRecordingIfNeeded()
            isShowingTranscription = true
        } else {
            if !viewModel.startRecording() {
                isShowingTranscription = true
            }
        }
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
        replacePendingVoiceRecording(with: recording.audioURL)
    }

    private func cleanupDraftRecordingIfNeeded() {
        captureActiveVoiceRecordingIfNeeded()

        if !didSaveEntry {
            viewModel.discardRecordingFile(at: pendingVoiceRecordingAudioURL)
        }

        pendingVoiceRecordingAudioURL = nil
    }

    private func replacePendingVoiceRecording(with audioURL: URL?) {
        guard let audioURL else {
            return
        }

        DiaryViewModel.removeReplacedRecordingFile(previous: pendingVoiceRecordingAudioURL, replacement: audioURL)
        pendingVoiceRecordingAudioURL = audioURL
    }
    
    // 辅助方法显示提示信息
    private func showToast(message: String) {
        // 使用视图模型的toast功能或在界面上显示提示
        viewModel.showToast(message: message)
    }
    
    private func handleRefinementAction() {
        // 将当前编辑的内容复制到transcribedText中处理
        viewModel.setTranscriptionText(content, inputSource: .editorContent)
        
        // 触发AI润色处理
        viewModel.refineTranscribedText(content, inputSource: .editorContent)
        
        // 显示转写界面，以便用户查看处理结果
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowingTranscription = true
        }
    }
    
    private var datePickerSheet: some View {
        NavigationStack {
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
                        isShowingDatePicker = false
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }
}

#Preview {
    let viewModel = PreviewHelpers.createViewModel()
    
    return NavigationStack {
        CreateDiaryView(viewModel: viewModel, isPresented: .constant(true))
            .navigationTitle("新建日记")
            .navigationBarTitleDisplayMode(.inline)
            .environmentObject(ThemeManager())
    }
    .modelContainer(PreviewHelpers.previewContainer)
}
