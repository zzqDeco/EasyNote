import SwiftUI

/// 控制标签选择的环境对象
class TabSelectionManager: ObservableObject {
    @Published var selectedTab: Binding<Int>
    
    init(selectedTab: Binding<Int>) {
        self.selectedTab = selectedTab
    }
    
    func switchToTab(_ tabIndex: Int) {
        selectedTab.wrappedValue = tabIndex
    }
} 