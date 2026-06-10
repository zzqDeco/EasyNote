import SwiftUI

// 转录结果显示组件 - 从NewDiaryView提取
struct TranscriptionDisplayView: View {
    @ObservedObject var viewModel: DiaryViewModel
    var isShowingTranscription: Bool
    var content: String
    
    @State private var processingDotsCount = 0
    @State private var processingTimer: Timer? = nil
    @State private var showOptions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(viewModel.isProcessingAI ? "AI处理中" : viewModel.transcribedText.isEmpty ? "内容润色" : "润色结果")
                    .font(.headline)
                    .fontWeight(.medium)
                
                if !viewModel.isProcessingAI && !viewModel.transcribedText.isEmpty {
                    Text("·")
                        .foregroundColor(.gray)
                    
                    Text(content.isEmpty ? "语音转写内容" : "当前编辑内容")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if viewModel.isProcessingAI {
                    // 显示处理指示器
                    ProgressView()
                        .scaleEffect(0.7)
                        .transition(.opacity)
                } else if !viewModel.transcribedText.isEmpty {
                    // 显示折叠/展开按钮
                    Button {
                        withAnimation {
                            showOptions.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showOptions ? "收起选项" : "显示选项")
                                .font(.footnote)
                            Image(systemName: showOptions ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            
            // 转写内容区域
            if !viewModel.isProcessingAI && !viewModel.transcribedText.isEmpty {
                transcriptionContentView
            } else if viewModel.isProcessingAI {
                processingView
            }
            
            // 操作按钮 - 仅当有内容且不在处理中时显示
            if !viewModel.transcribedText.isEmpty && !viewModel.isProcessingAI && showOptions {
                actionButtonsView
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .onDisappear {
            cleanupTimer()
        }
    }
    
    // MARK: - 子视图
    
    private var processingView: some View {
        VStack(alignment: .center, spacing: 10) {
            // 使用更简洁的处理指示器
            ProgressView()
                .scaleEffect(1.2)
                .padding(.bottom, 8)
            
            Text("AI正在润色您的内容...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private var transcriptionContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 添加内容来源说明
            if !content.isEmpty {
                Text("润色前内容：")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            // 显示转写文本区域
            ScrollView {
                Text(viewModel.transcribedText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .frame(maxHeight: 200)
        }
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.vertical, 4)
            
            // 添加轻量提示
            Text("选择如何处理润色后的内容")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
            
            HStack(spacing: 16) {
                // 润色按钮
                Button {
                    viewModel.refineTranscribedText(viewModel.transcribedText)
                } label: {
                    actionButton(
                        icon: "wand.and.stars",
                        text: "润色",
                        color: .purple
                    )
                }
                .disabled(viewModel.isProcessingAI)
                
                // 扩展按钮
                Button {
                    viewModel.expandTranscribedText(viewModel.transcribedText)
                } label: {
                    actionButton(
                        icon: "arrow.up.and.down.text.horizontal",
                        text: "扩展",
                        color: .blue
                    )
                }
                .disabled(viewModel.isProcessingAI)
                
                // 总结按钮
                Button {
                    viewModel.summarizeTranscribedText(viewModel.transcribedText)
                } label: {
                    actionButton(
                        icon: "text.redaction",
                        text: "总结",
                        color: .green
                    )
                }
                .disabled(viewModel.isProcessingAI)
            }
            
            HStack(spacing: 16) {
                // 替换按钮
                Button {
                    NotificationCenter.default.post(
                        name: Notification.Name("UseTranscribedContent"),
                        object: viewModel.transcribedText,
                        userInfo: ["replace": true]
                    )
                    
                    // 立即清空转写内容，避免重复使用
                    DispatchQueue.main.async {
                        viewModel.transcribedText = ""
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("替换内容")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // 追加按钮
                Button {
                    NotificationCenter.default.post(
                        name: Notification.Name("UseTranscribedContent"),
                        object: viewModel.transcribedText,
                        userInfo: ["replace": false]
                    )
                    
                    // 立即清空转写内容，避免重复使用
                    DispatchQueue.main.async {
                        viewModel.transcribedText = ""
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("追加到内容")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.top, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private func actionButton(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.headline)
            Text(text)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - 辅助方法
    
    private func cleanupTimer() {
        processingTimer?.invalidate()
        processingTimer = nil
    }
}

// MARK: - Lottie动画视图
struct LottieView: View {
    let name: String
    
    var body: some View {
        // 注意：这是一个占位实现
        // 在实际应用中，您需要集成Lottie库
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.1))
            
            // 简单的加载动画模拟
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
        }
    }
}

#Preview {
    // 使用预览辅助工具创建一个一致的预览环境
    let viewModel = PreviewHelpers.createViewModel()
    // 手动设置一些预览数据
    viewModel.transcribedText = "这是一段预览用的转写文本，用于展示界面布局。添加一些额外内容让文本看起来更长一些，以便测试滚动视图和其他UI元素的布局效果。"
    
    return TranscriptionDisplayView(
        viewModel: viewModel,
        isShowingTranscription: true,
        content: "日记内容"
    )
    .padding()
    .modelContainer(PreviewHelpers.previewContainer)
} 