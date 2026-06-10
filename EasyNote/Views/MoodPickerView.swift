import SwiftUI

struct MoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMood: Int
    
    let moods = [
        (1, "😢", "很糟"),
        (2, "😔", "不好"),
        (3, "😐", "一般"),
        (4, "😊", "不错"),
        (5, "😁", "很棒"),
        (6, "😡", "愤怒"),
        (7, "😱", "恐惧"),
        (8, "😨", "焦虑"),
        (9, "🤔", "思考"),
        (10, "😴", "疲倦"),
        (11, "🥳", "兴奋"),
        (12, "😂", "搞笑"),
        (13, "🥰", "爱意"),
        (14, "😇", "感恩"),
        (15, "😎", "自信"),
        (16, "😌", "放松")
    ]
    
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
                        ForEach(moods, id: \.0) { mood in
                            VStack {
                                Text(mood.1)
                                    .font(.system(size: 30))
                                Text(mood.2)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(selectedMood == mood.0 ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedMood == mood.0 ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                selectedMood = mood.0
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
        default: return "未知心情"
        }
    }
    
    static func moodStringValue(for mood: Int) -> String {
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
        default: return "一般"
        }
    }
    
    static func moodIcon(for mood: Int) -> String {
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
}

#Preview {
    MoodPickerView(selectedMood: .constant(3))
} 