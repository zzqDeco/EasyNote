import SwiftUI
import SwiftData

struct AIFunctionsView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("请选择AI功能")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    Button {
                        // 生成摘要
                        viewModel.generateAISummary()
                        dismiss() // 关闭选择视图
                    } label: {
                        AIFunctionCard(
                            title: "生成日记摘要",
                            description: "使用DeepSeek AI分析您的日记内容，提取关键点并生成简洁的摘要",
                            icon: "doc.text.magnifyingglass",
                            color: .purple
                        )
                    }
                    
                    // 已移除推荐日程安排卡片
                    
                    // 设置API密钥
                    Button {
                        // 打开设置页面
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    } label: {
                        AIFunctionCard(
                            title: "设置DeepSeek API密钥",
                            description: "配置您的DeepSeek API密钥以启用AI功能",
                            icon: "key",
                            color: .gray
                        )
                    }
                    
                    // 介绍文本
                    Text("只有在您明确授权后，所选日记文本或生成推荐所需的近期日记才会发送给 DeepSeek；录音音频文件不会发送。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .padding(.vertical)
            }
            .navigationBarTitle("AI功能", displayMode: .inline)
            .navigationBarItems(trailing: Button("关闭") {
                dismiss()
            })
        }
    }
}

struct AIFunctionCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(color)
                .cornerRadius(15)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    let previewContainer = try! ModelContainer(for: DiaryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    
    let viewModel = DiaryViewModel(modelContext: previewContainer.mainContext)
    
    AIFunctionsView(viewModel: viewModel)
}
