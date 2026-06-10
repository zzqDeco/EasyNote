//
//  DiaryDetailView.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import SwiftUI
import AVFoundation
import SwiftData

struct DiaryDetailView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @EnvironmentObject private var tabManager: TabSelectionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let entry: DiaryEntry
    
    @State private var isEditingEntry = false
    @State private var isCreatingNewEntry = false
    @State private var showShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isGeneratingAISummary = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlayingAudio = false
    @State private var audioProgress: Double = 0
    @State private var audioTimer: Timer?
    @State private var refreshTrigger = false
    @State private var isLoading = true
    @State private var showCopySuccessToast = false
    @State private var isFavorite: Bool
    @State private var audioPlayerDelegate: AVPlayerDelegate?
    
    init(viewModel: DiaryViewModel, entry: DiaryEntry) {
        self.viewModel = viewModel
        self.entry = entry
        // 初始化收藏状态
        _isFavorite = State(initialValue: entry.isFavorite)
    }
    
    var body: some View {
        ZStack {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 标题区域
                    titleSection
                    
                    // 内容区域
                    contentSection
                        .contextMenu {
                            Button(action: {
                                copyContent()
                            }) {
                                Label("复制内容", systemImage: "doc.on.doc")
                            }
                            
                            Button(action: {
                                copyFullEntry()
                            }) {
                                Label("复制全部", systemImage: "square.on.square")
                            }
                        }
                    
                    // AI摘要区域（如果有）
                    if let summary = entry.aiSummary, !summary.isEmpty {
                        aiSummarySection(summary)
                            .contextMenu {
                                Button(action: {
                                    copySummary()
                                }) {
                                    Label("复制摘要", systemImage: "doc.on.doc")
                                }
                            }
                    } else {
                        generateAISummaryButton
                    }
                    
                    // 元数据区域（标签和心情）
                    metadataSection
                    
                    // 音频附件（如果有）
                    if entry.audioURL != nil {
                        audioAttachmentSection
                    }
                    
                    Spacer(minLength: 70)
                }
                .padding()
                .opacity(isLoading ? 0 : 1)
            }
            .navigationTitle("日记详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        toggleFavorite()
                    }) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundColor(isFavorite ? .yellow : .gray)
                    }
                    .animation(.spring(response: 0.3), value: isFavorite)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            isEditingEntry = true
                        }) {
                            Label("编辑", systemImage: "pencil")
                        }
                        
                        Button(action: {
                            isCreatingNewEntry = true
                        }) {
                            Label("写新日记", systemImage: "plus.square")
                        }
                        
                        Menu {
                            Button(action: {
                                copyTitle()
                            }) {
                                Label("复制标题", systemImage: "textformat")
                            }
                            
                            Button(action: {
                                copyContent()
                            }) {
                                Label("复制内容", systemImage: "doc.text")
                            }
                            
                            if let summary = entry.aiSummary, !summary.isEmpty {
                                Button(action: {
                                    copySummary()
                                }) {
                                    Label("复制摘要", systemImage: "wand.and.stars")
                                }
                            }
                            
                            Button(action: {
                                copyFullEntry()
                            }) {
                                Label("复制全部", systemImage: "square.on.square")
                            }
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        
                        Button(action: {
                            toggleFavorite()
                        }) {
                            Label(isFavorite ? "取消收藏" : "收藏", 
                                  systemImage: isFavorite ? "star.slash" : "star")
                        }
                        
                        Button(action: {
                            showShareSheet = true
                        }) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: {
                            showingDeleteConfirmation = true
                        }) {
                            Label("删除", systemImage: "trash")
                        }
                } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            
            if isLoading {
                ProgressView("加载中...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.2)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Material.regularMaterial)
                    )
            }
            
            // 复制成功提示
            if showCopySuccessToast {
                VStack {
                    Spacer()
                    Text("已复制到剪贴板")
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Material.thin)
                        )
                        .foregroundColor(.primary)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(2)
            }
        }
        .sheet(isPresented: $isEditingEntry, onDismiss: {
            refreshTrigger.toggle()  // 触发界面刷新
        }) {
            NavigationStack {
                DiaryEditView(viewModel: viewModel, entry: entry)
            }
            .environmentObject(tabManager)
        }
        .sheet(isPresented: $isCreatingNewEntry) {
            NavigationStack {
                CreateDiaryView(viewModel: viewModel, isPresented: $isCreatingNewEntry)
            }
            .environmentObject(tabManager)
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("删除", role: .destructive) {
                viewModel.deleteEntry(entry)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除这篇日记吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showShareSheet) {
            let content = """
            标题: \(entry.title)
            日期: \(formatDate(entry.creationDate))
            
            \(entry.content)
            
            #\(entry.tags.joined(separator: " #"))
            """
            
            ActivityViewController(activityItems: [content])
        }
        .onAppear {
            // 设置当前条目
                    viewModel.currentEntry = entry
            
            // 模拟短暂的加载状态
            isLoading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isLoading = false
            }
            
            // 更新收藏状态
            isFavorite = entry.isFavorite
        }
        .onDisappear {
            // 停止音频播放
            stopAudio()
        }
        .overlay(
            VStack {
                Spacer()
                
                Button(action: {
                    isCreatingNewEntry = true
                }) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("写新日记")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    .shadow(radius: 3)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        )
        .onChange(of: refreshTrigger) { oldValue, newValue in
            // 当编辑视图关闭时，此处会被触发刷新UI
            viewModel.currentEntry = entry
            isFavorite = entry.isFavorite
        }
        .onChange(of: viewModel.isProcessingAI) { oldValue, newValue in
            // 当AI处理完成时刷新界面
            if !newValue && isGeneratingAISummary {
                isGeneratingAISummary = false
            }
        }
        .onChange(of: viewModel.errorMessage) { oldValue, newValue in
            // 处理错误消息
            if newValue != nil {
                // 可以在这里显示错误提示
                print("错误: \(newValue ?? "")")
            }
        }
    }
    
    // MARK: - 收藏功能
    private func toggleFavorite() {
        isFavorite.toggle()
        entry.isFavorite = isFavorite
        
        // 保存更改
        viewModel.updateCurrentEntry()
        
        // 提供触觉反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // MARK: - 复制功能
    
    private func copyTitle() {
        UIPasteboard.general.string = entry.title
        showCopyToast()
    }
    
    private func copyContent() {
        UIPasteboard.general.string = entry.content
        showCopyToast()
    }
    
    private func copySummary() {
        if let summary = entry.aiSummary, !summary.isEmpty {
            UIPasteboard.general.string = summary
            showCopyToast()
        }
    }
    
    private func copyFullEntry() {
        let formattedEntry = """
        标题: \(entry.title)
        日期: \(formatDate(entry.creationDate))
        
        \(entry.content)
        
        \(entry.aiSummary != nil ? "AI摘要: \(entry.aiSummary!)\n" : "")
        \(entry.mood != nil ? "心情: \(entry.mood!)\n" : "")
        \(entry.tags.isEmpty ? "" : "标签: #\(entry.tags.joined(separator: " #"))")
        """
        
        UIPasteboard.general.string = formattedEntry
        showCopyToast()
    }
    
    private func showCopyToast() {
        withAnimation {
            showCopySuccessToast = true
        }
        
        // 2秒后隐藏提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopySuccessToast = false
            }
        }
    }
    
    // MARK: - 子视图
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 日期显示 - 更加醒目
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                
                Text(formatDate(entry.creationDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Spacer()
                
                // 收藏图标
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.headline)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // 标题文本
            Text(entry.title)
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
        }
    }
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内容")
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
            
            Text(entry.content)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    private func aiSummarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI摘要")
                    .font(.headline)
                    .foregroundColor(.primary.opacity(0.8))
                
                Spacer()
                
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
            }
            
            Text(summary)
                .font(.body)
                .italic()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    private var generateAISummaryButton: some View {
        Button {
            isGeneratingAISummary = true
            viewModel.generateAISummary()
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("生成AI摘要")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.purple.opacity(0.1))
            )
            .cornerRadius(12)
        }
        .disabled(viewModel.isProcessingAI)
        .overlay(
            Group {
                if viewModel.isProcessingAI {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("正在生成...")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.1))
                    )
                    .cornerRadius(12)
                }
            }
        )
    }
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let mood = entry.mood {
                HStack {
                    Text("心情:")
                        .font(.headline)
                        .foregroundColor(.primary.opacity(0.8))
                    
                    Text(getMoodDisplayText(mood))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            
            if !entry.tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("标签:")
                        .font(.headline)
                        .foregroundColor(.primary.opacity(0.8))
                    
                    FlowLayout(
                        mode: .scrollable,
                        items: entry.tags,
                        itemSpacing: 8
                    ) { tag in
                        Text(tag)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
            }
        }
    }
    
    private var audioAttachmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语音记录")
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
            
            Button {
                toggleAudioPlayback()
            } label: {
                HStack {
                    Image(systemName: isPlayingAudio ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    Text(isPlayingAudio ? "暂停" : "播放录音")
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    if isPlayingAudio {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.7)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
            }
            
            if isPlayingAudio {
                VStack(alignment: .leading, spacing: 4) {
                    // 音频进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                                .cornerRadius(2)
                            
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * CGFloat(audioProgress), height: 4)
                                .cornerRadius(2)
                        }
                    }
                    .frame(height: 4)
                    .padding(.vertical, 8)
                    
                    // 当前播放时间
                    HStack {
                        if let player = audioPlayer {
                            Text(formatTimeInterval(player.currentTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(formatTimeInterval(player.duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private func formatTimeInterval(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func toggleAudioPlayback() {
        if isPlayingAudio {
            stopAudio()
        } else {
            playAudio()
        }
    }
    
    private func playAudio() {
        guard let audioURL = entry.audioURL else { return }
        
        do {
            // 设置和激活音频会话
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 创建委托对象并保存强引用
            audioPlayerDelegate = AVPlayerDelegate(onFinish: {
                stopAudio()
            })
            
            // 创建音频播放器
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = audioPlayerDelegate
            audioPlayer?.prepareToPlay()
            
            // 开始播放
            if audioPlayer?.play() == true {
                isPlayingAudio = true
                
                // 创建一个定时器来更新进度
                audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let player = audioPlayer {
                        audioProgress = player.currentTime / player.duration
                    }
                }
            }
        } catch {
            print("音频播放错误: \(error.localizedDescription)")
        }
    }
    
    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerDelegate = nil  // 清除委托对象的引用
        isPlayingAudio = false
        audioProgress = 0
        audioTimer?.invalidate()
        audioTimer = nil
        
        // 停用音频会话
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("停用音频会话错误: \(error.localizedDescription)")
        }
    }
    
    // 获取心情显示文本
    private func getMoodDisplayText(_ mood: String) -> String {
        if let moodInt = Int(mood) {
            return MoodPickerView.moodText(for: moodInt)
        } else {
            return mood
        }
    }
}

// MARK: - 音频播放委托
class AVPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onFinish()
        }
    }
}

// MARK: - 活动视图控制器包装器
struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 流式布局
struct FlowLayout<T: Hashable, V: View>: View {
    enum Mode {
        case scrollable
        case vstack
    }
    
    let mode: Mode
    let items: [T]
    let itemSpacing: CGFloat
    let itemBuilder: (T) -> V
    
    var body: some View {
        switch mode {
        case .scrollable:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: itemSpacing) {
                    ForEach(items, id: \.self) { item in
                        itemBuilder(item)
                    }
                }
            }
        case .vstack:
            VStack(alignment: .leading, spacing: itemSpacing) {
                ForEach(items, id: \.self) { item in
                    itemBuilder(item)
                }
            }
        }
    }
}

#Preview {
    let viewModel = PreviewHelpers.createViewModel()
    let entry = PreviewHelpers.sampleEntry
    
    NavigationStack {
        DiaryDetailView(viewModel: viewModel, entry: entry)
    }
    .environmentObject(PreviewHelpers.tabManager)
    .modelContainer(PreviewHelpers.previewContainer)
}
