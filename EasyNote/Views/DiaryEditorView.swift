import SwiftUI
import SwiftData
import AVFoundation

struct DiaryEditorView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @EnvironmentObject private var tabManager: TabSelectionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var mood: Int = 1
    @State private var tags: [String] = []
    @State private var showingMoodPicker = false
    @State private var showingTagEditor = false
    @State private var persistenceError: String?
    
    // 音频录制相关状态
    @State private var isRecording = false
    @State private var audioURL: URL?
    @State private var showingAudioRecorder = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let persistenceError {
                        Text(persistenceError)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    // 日记标题输入
                    TextField("标题", text: $title)
                        .font(.title)
                        .padding(.horizontal)
                    
                    // 当前日期显示
                    Text(formattedCurrentDate())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    // 心情选择器
                    Button(action: {
                        showingMoodPicker = true
                    }) {
                        HStack {
                            Text("心情：")
                            Text(moodToEmoji(mood))
                                .font(.title2)
                        }
                        .padding(.horizontal)
                    }
                    
                    // 标签显示
                    HStack {
                        Text("标签：")
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(tags, id: \.self) { tag in
                                    Text(tag)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(8)
                                }
                                
                                Button(action: {
                                    showingTagEditor = true
                                }) {
                                    Image(systemName: "plus")
                                        .padding(6)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // 日记内容编辑区
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationBarTitle("新建日记", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") {
                    // 返回到日记列表
                    tabManager.selectedTab.wrappedValue = 0  // 对应Tab.diary
                },
                trailing: Button("保存") {
                    saveEntry()
                }
                .disabled(title.isEmpty && content.isEmpty)
            )
            .sheet(isPresented: $showingMoodPicker) {
                MoodPickerView(selectedMood: $mood)
            }
            .sheet(isPresented: $showingTagEditor) {
                TagEditorView(tags: $tags)
            }
        }
    }
    
    // 保存日记条目
    private func saveEntry() {
        let newEntry = viewModel.createNewEntry(
            title: title.isEmpty ? "无标题" : title,
            content: content,
            mood: moodToString(mood),
            tags: tags
        )

        let feedback = PersistenceFeedback.resolve(
            succeeded: newEntry != nil,
            viewModelError: viewModel.errorMessage,
            fallbackError: "保存日记失败，请重试"
        )
        persistenceError = feedback.errorMessage

        guard feedback.shouldDismiss else { return }
        
        // 重置输入并返回到日记列表
        title = ""
        content = ""
        mood = 1
        tags = []
        
        // 跳转到日记列表选项卡
        tabManager.selectedTab.wrappedValue = 0  // 对应Tab.diary
    }
    
    // 格式化当前日期
    private func formattedCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: Date())
    }
    
    // 将心情值转换为表情
    private func moodToEmoji(_ mood: Int) -> String {
        switch mood {
        case 0: return "😢" // 悲伤
        case 1: return "😐" // 平静
        case 2: return "😊" // 开心
        case 3: return "😀" // 兴奋
        case 4: return "😍" // 喜爱
        default: return "😐"
        }
    }
    
    // 将心情值转换为字符串
    private func moodToString(_ mood: Int) -> String {
        switch mood {
        case 0: return "伤心"
        case 1: return "平静"
        case 2: return "开心"
        case 3: return "兴奋"
        case 4: return "喜爱"
        default: return "平静"
        }
    }
}

#Preview {
    DiaryEditorView(viewModel: PreviewHelpers.createViewModel())
        .environmentObject(PreviewHelpers.tabManager)
}
