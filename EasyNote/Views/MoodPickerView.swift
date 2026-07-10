import SwiftUI

struct MoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMood: Int
    
    // 定义列数，根据屏幕大小调整
    let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 15),
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 15),
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 15)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    Text("今天的心情如何？")
                        .font(.headline)
                        .padding()
                    
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(MoodCatalog.options) { mood in
                            VStack {
                                Text(mood.emoji)
                                    .font(.system(size: 30))
                                Text(mood.label)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(selectedMood == mood.id ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedMood == mood.id ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                selectedMood = mood.id
                                // 添加触感反馈
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                            }
                        }
                    }
                    .padding(.bottom, 60)
                }
                .padding()
            }
            .navigationBarTitle("选择心情", displayMode: .inline)
            .navigationBarItems(trailing: Button("完成") {
                dismiss()
            })
        }
    }
}

// 扩展MoodPickerView以提供共享的心情转换方法
extension MoodPickerView {
    static func moodText(for mood: Int) -> String {
        MoodCatalog.displayText(for: mood)
    }
    
    static func moodStringValue(for mood: Int) -> String {
        MoodCatalog.storedLabel(for: mood)
            ?? MoodCatalog.storedLabel(for: MoodCatalog.defaultIndex)
            ?? "一般"
    }
    
    static func moodIcon(for mood: Int) -> String {
        MoodCatalog.options.first { $0.id == mood }?.systemImage ?? "sun.min"
    }
}

#Preview {
    MoodPickerView(selectedMood: .constant(3))
}
