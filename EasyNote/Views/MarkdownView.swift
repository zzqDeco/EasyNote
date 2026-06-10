import SwiftUI
import SwiftData

#if canImport(MarkdownUI)
import MarkdownUI

struct MarkdownView: View {
    let content: String
    let backgroundColor: Color
    
    init(_ content: String, backgroundColor: Color = .clear) {
        self.content = content
        self.backgroundColor = backgroundColor
    }
    
    var body: some View {
        Markdown(content)
            .markdownTheme(.basic)
            .padding(8)
            .background(backgroundColor)
            .cornerRadius(8)
    }
}
#else
// 简单的Markdown渲染视图，当MarkdownUI不可用时
struct MarkdownView: View {
    let content: String
    let backgroundColor: Color
    
    init(_ content: String, backgroundColor: Color = .clear) {
        self.content = content
        self.backgroundColor = backgroundColor
    }
    
    var body: some View {
        // 简单的文本显示
        VStack(alignment: .leading) {
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(backgroundColor)
                .cornerRadius(8)
        }
    }
}
#endif

#Preview {
    MarkdownView("""
    # 标题
    
    这是正文内容
    
    ## 子标题
    
    - 列表项1
    - 列表项2
    
    **粗体文本** 和 *斜体文本*
    """, backgroundColor: Color.gray.opacity(0.1))
} 