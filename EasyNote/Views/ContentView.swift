import SwiftUI
import SwiftData

// 颜色扩展 - 提供混合功能
extension Color {
    func blended(with color: Color, factor: CGFloat = 0.5) -> Color {
        // 模拟颜色混合效果
        self
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ContentRootView(modelContext: modelContext)
    }
}

private struct ContentRootView: View {
    private let modelContext: ModelContext
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var tabBarController = TabBarController()
    @StateObject private var tabSelectionManager = TabSelectionManager(selectedTab: .constant(0))
    @State private var showingUnifiedAddSheet = false
    @State private var showingCreateDiarySheet = false
    @State private var addingType: AddingContentType = .diary
    @StateObject private var diaryViewModel: DiaryViewModel
    @StateObject private var exploreViewModel: ExploreViewModel
    @StateObject private var todoViewModel: TodoViewModel
    
    // 添加一个State变量用于强制重新渲染TabView
    @State private var tabViewRefreshKey = UUID()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _diaryViewModel = StateObject(wrappedValue: DiaryViewModel(modelContext: modelContext))
        _exploreViewModel = StateObject(wrappedValue: ExploreViewModel(modelContext: modelContext))
        _todoViewModel = StateObject(wrappedValue: TodoViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        Group {
            ZStack(alignment: .bottom) {
                // 使用tabViewRefreshKey作为TabView的id，强制在主题变化时重新渲染
                TabView(selection: $tabBarController.selectedTab) {
                    // 新的探索页（AI聊天）
                    ChatExploreView(
                        diaryViewModel: diaryViewModel,
                        modelContext: modelContext
                    )
                        .environment(\.colorScheme, themeManager.colorScheme)
                        .tabItem {
                            Label("探索", systemImage: "magnifyingglass.circle")
                        }
                        .tag(Tab.explore)
                    
                    // 待办页面（原探索页面更名）
                    ExploreView(
                        viewModel: exploreViewModel,
                        todoViewModel: todoViewModel
                    )
                        .environment(\.colorScheme, themeManager.colorScheme)
                        .tabItem {
                            Label("待办", systemImage: "checkmark.circle")
                        }
                        .tag(Tab.todo)
                    
                    // 日记页
                    DiaryListView(viewModel: diaryViewModel)
                        .environment(\.colorScheme, themeManager.colorScheme)
                        .tabItem {
                            Label("日记", systemImage: "book.closed")
                        }
                        .tag(Tab.diary)
                    
                    // 设置页
                    SettingsView(themeManager: themeManager)
                        .environment(\.colorScheme, themeManager.colorScheme)
                        .tabItem {
                            Label("设置", systemImage: "gearshape")
                        }
                        .tag(Tab.settings)
                }
                .id(tabViewRefreshKey) // 使用id修饰符强制在key变化时重新创建TabView
                .tint(themeManager.accentColor)
                
                // 添加悬浮按钮
                if tabBarController.selectedTab != .settings && tabBarController.selectedTab != .explore {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                // 根据当前选中的标签页决定要添加的内容类型
                                switch tabBarController.selectedTab {
                                case .todo:
                                    addingType = .todo
                                    showingUnifiedAddSheet = true
                                case .diary:
                                    // 设置当前的DiaryViewModel
                                    diaryViewModel.updateModelContext(modelContext)
                                    showingCreateDiarySheet = true
                                default:
                                    break
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [themeManager.accentColor, Color.purple.opacity(0.8)]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .shadow(color: themeManager.accentColor.opacity(0.3), radius: 5, x: 0, y: 3)
                                    )
                                    // 添加id确保主题色变化时按钮重绘
                                    .id("add-button-\(themeManager.accentColorName)")
                            }
                            .padding(.bottom, 80)
                            .padding(.trailing, 20)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingUnifiedAddSheet) {
                NavigationStack {
                    UnifiedAddView(
                        todoViewModel: todoViewModel,
                        isPresented: $showingUnifiedAddSheet,
                        contentType: $addingType
                    )
                    .navigationTitle("新建待办")
                    .navigationBarTitleDisplayMode(.inline)
                    .environment(\.colorScheme, themeManager.colorScheme)
                }
                .environmentObject(tabSelectionManager)
                .environmentObject(tabBarController)
                .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingCreateDiarySheet, onDismiss: {
                // 重置视图模型，避免重复使用
                diaryViewModel.transcribedText = ""
            }) {
                NavigationStack {
                    CreateDiaryView(
                        viewModel: diaryViewModel,
                        isPresented: $showingCreateDiarySheet
                    )
                    .navigationTitle("新建日记")
                    .navigationBarTitleDisplayMode(.inline)
                    .environment(\.colorScheme, themeManager.colorScheme)
                    .onAppear {
                        // 确保每次打开时都重新设置视图模型
                        diaryViewModel.transcribedText = ""
                        diaryViewModel.updateModelContext(modelContext)
                    }
                }
                .environmentObject(tabSelectionManager)
                .environmentObject(tabBarController)
                .environmentObject(themeManager)
            }
            .onAppear {
                // 初始设置UI外观
                updateAppearance()
                
                // 当标签改变时，更新TabSelectionManager
                let tabIndex: Int
                switch tabBarController.selectedTab {
                case .explore: tabIndex = 0
                case .todo: tabIndex = 1
                case .diary: tabIndex = 2
                case .settings: tabIndex = 3
                }
                tabSelectionManager.selectedTab.wrappedValue = tabIndex
            }
            .onChange(of: tabBarController.selectedTab) { _, newTab in
                // 当标签改变时，更新TabSelectionManager
                let tabIndex: Int
                switch newTab {
                case .explore: tabIndex = 0
                case .todo: tabIndex = 1
                case .diary: tabIndex = 2
                case .settings: tabIndex = 3
                }
                tabSelectionManager.selectedTab.wrappedValue = tabIndex
            }
            .onChange(of: themeManager.accentColorName) { _, _ in
                // 当主题颜色变化时，更新UI并强制重绘TabView
                updateAppearance()
                // 生成新的UUID，强制TabView重新渲染
                tabViewRefreshKey = UUID()
            }
            .onChange(of: themeManager.colorScheme) { _, _ in
                // 当深色模式变化时，更新UI并强制重绘TabView
                updateAppearance()
                // 生成新的UUID，强制TabView重新渲染
                tabViewRefreshKey = UUID()
            }
            .environmentObject(tabBarController)
            .environmentObject(tabSelectionManager)
            .environmentObject(themeManager)
        }
        .preferredColorScheme(themeManager.colorScheme)
    }
    
    // 更新UI外观
    private func updateAppearance() {
        // 更新标签栏外观
        UITabBar.appearance().backgroundColor = UIColor(themeManager.tabBarBackgroundColor)
        UITabBar.appearance().tintColor = UIColor(themeManager.accentColor)
        
        // iOS 15+ 新API设置标签栏外观
        if #available(iOS 15.0, *) {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            tabBarAppearance.stackedLayoutAppearance.normal.iconColor = .gray
            tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(themeManager.accentColor)
            tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(themeManager.accentColor)]
            
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            UITabBar.appearance().standardAppearance = tabBarAppearance
            
            // 寻找当前所有TabBar实例，强制更新它们的外观
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                for window in windowScene.windows {
                    for view in window.subviews {
                        view.setNeedsLayout()
                    }
                    
                    // 查找并更新所有TabBar
                    if let rootVC = window.rootViewController {
                        updateTabBars(in: rootVC)
                    }
                }
            }
        }
    }
    
    // 递归查找并更新所有TabBar实例
    private func updateTabBars(in viewController: UIViewController) {
        if let tabBarController = viewController as? UITabBarController {
            // 直接更新这个TabBar的tintColor
            tabBarController.tabBar.tintColor = UIColor(themeManager.accentColor)
            
            // 如果使用iOS 15+的新API，也更新standardAppearance和scrollEdgeAppearance
            if #available(iOS 15.0, *) {
                let tabBarAppearance = UITabBarAppearance()
                tabBarAppearance.configureWithDefaultBackground()
                tabBarAppearance.stackedLayoutAppearance.normal.iconColor = .gray
                tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(themeManager.accentColor)
                tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(themeManager.accentColor)]
                
                tabBarController.tabBar.standardAppearance = tabBarAppearance
                tabBarController.tabBar.scrollEdgeAppearance = tabBarAppearance
            }
            
            // 强制TabBar重新布局
            tabBarController.tabBar.setNeedsLayout()
        }
        
        // 检查子视图控制器
        for child in viewController.children {
            updateTabBars(in: child)
        }
        
        // 检查presented视图控制器
        if let presented = viewController.presentedViewController {
            updateTabBars(in: presented)
        }
    }
}

// 添加内容类型枚举
enum AddingContentType {
    case diary
    case todo
}

// 应用中的主要标签页
enum Tab: String {
    case explore = "explore"  // 新的探索页面（AI聊天）
    case todo = "todo"        // 原探索页面改为待办
    case diary = "diary"
    case settings = "settings"
}

// 用于控制TabView行为的ObservableObject
class TabBarController: ObservableObject {
    @Published var selectedTab: Tab = .explore
    
    func switchToTab(_ tab: Tab) {
        selectedTab = tab
    }
}

// 主题管理器
class ThemeManager: ObservableObject {
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("accentColorName") var accentColorName = "blue"
    
    var colorScheme: ColorScheme {
        darkModeEnabled ? .dark : .light
    }
    
    var accentColor: Color {
        switch accentColorName {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "red": return .red
        case "orange": return .orange
        default: return .blue
        }
    }
    
    // 标签栏背景色
    var tabBarBackgroundColor: Color {
        if darkModeEnabled {
            // 深色模式下使用系统背景色
            return Color(UIColor.systemBackground)
        } else {
            return Color.white
        }
    }
    
    func toggleDarkMode() {
        darkModeEnabled.toggle()
        // 发送通知告知深色模式已变更
        NotificationCenter.default.post(name: Notification.Name("ThemeColorSchemeChanged"), object: nil)
    }
    
    func setAccentColor(_ name: String) {
        accentColorName = name
        // 发送通知告知主题色已变更
        NotificationCenter.default.post(name: Notification.Name("ThemeAccentColorChanged"), object: name)
    }
}

// 预览
#Preview {
    ContentView()
        .modelContainer(for: [DiaryEntry.self, TodoItem.self, ChatSession.self, SessionMessage.self], inMemory: true)
} 
