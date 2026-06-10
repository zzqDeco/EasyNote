import SwiftUI
import SwiftData

/// 预览辅助工具，提供统一的预览数据和ModelContainer
enum PreviewHelpers {
    /// 创建轻量级的预览容器
    static let previewContainer: ModelContainer = {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: DiaryEntry.self, configurations: config)
        } catch {
            fatalError("创建预览ModelContainer失败: \(error)")
        }
    }()
    
    /// 创建一个预览用的DiaryViewModel
    @MainActor
    static func createViewModel() -> DiaryViewModel {
        let context = previewContainer.mainContext
        
        // 添加示例数据
        let sampleEntry = DiaryEntry(
            title: "预览日记标题",
            content: "这是一篇用于预览的日记内容。\n包含多行文本来测试界面布局。",
            mood: "开心",
            tags: ["预览", "测试"]
        )
        
        context.insert(sampleEntry)
        
        // 创建ViewModel实例
        let viewModel = DiaryViewModel(modelContext: context)
        // 设置当前条目
        viewModel.currentEntry = sampleEntry
        
        return viewModel
    }
    
    /// 创建一个预览用的TabSelectionManager
    static let tabManager = TabSelectionManager(selectedTab: .constant(0))
    
    /// 创建一个预览用的DiaryEntry
    static let sampleEntry = DiaryEntry(
        title: "预览标题",
        content: "预览内容示例，用于展示界面。",
        mood: "平静",
        tags: ["预览"]
    )
} 