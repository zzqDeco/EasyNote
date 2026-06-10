//
//  DiaryListView.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import SwiftUI
import SwiftData

struct DiaryListView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @EnvironmentObject private var tabManager: TabSelectionManager
    @State private var searchText = ""
    @State private var isAddingEntry = false
    @State private var showingDeleteConfirmation = false
    @State private var entryToDelete: DiaryEntry?
    @State private var scrollToTop = false
    @State private var selectedFilterTag: String?
    @State private var selectedSortOption = SortOption.dateDesc
    @State private var showingFilterSheet = false
    @State private var showingSearchResults = false
    
    // 用于动画的状态
    @State private var listOpacity = 0.0
    @State private var refreshTrigger = false
    
    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc = "最新优先"
        case dateAsc = "最早优先"
        case titleAsc = "标题升序"
        case titleDesc = "标题降序"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主列表内容
                VStack(spacing: 0) {
                    // 搜索栏
                    searchBar
                    
                    // 筛选栏
                    filterBar
                    
                    if viewModel.entries.isEmpty {
                        emptyStateView
                    } else {
                        // 日记列表
                        diaryList
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.entries.count)
                .animation(.easeInOut(duration: 0.3), value: selectedFilterTag)
                .animation(.easeInOut(duration: 0.3), value: selectedSortOption)
            }
            .navigationTitle("日记")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                withAnimation(.easeIn(duration: 0.5)) {
                    listOpacity = 1.0
                }
            }
            .sheet(isPresented: $isAddingEntry) {
                addEntrySheet
            }
            .sheet(isPresented: $showingFilterSheet) {
                filterSheet
            }
            .alert("确认删除", isPresented: $showingDeleteConfirmation) {
                Button("删除", role: .destructive) {
                    if let entry = entryToDelete {
                        viewModel.deleteEntry(entry)
                    }
                    entryToDelete = nil
                }
                Button("取消", role: .cancel) {
                    entryToDelete = nil
                }
            } message: {
                Text("确定要删除这篇日记吗？此操作不可撤销。")
            }
            .refreshable {
                await refreshData()
            }
        }
    }
    
    // MARK: - 子视图
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索日记...", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.searchEntries(searchText)
                    showingSearchResults = !searchText.isEmpty
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    viewModel.loadEntries()
                    showingSearchResults = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 筛选按钮
                Button {
                    showingFilterSheet = true
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("筛选")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // 排序显示
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(selectedSortOption.rawValue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)
                
                // 标签筛选显示
                if let tag = selectedFilterTag {
                    HStack {
                        Text("标签: \(tag)")
                        Button {
                            selectedFilterTag = nil
                            viewModel.loadEntries()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                
                if showingSearchResults {
                    HStack {
                        Text("搜索: \(searchText)")
                        Button {
                            searchText = ""
                            viewModel.loadEntries()
                            showingSearchResults = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private var diaryList: some View {
        List {
            ForEach(groupedEntries.keys.sorted(by: >), id: \.self) { dateString in
                Section(header: Text(dateString)) {
                    ForEach(groupedEntries[dateString] ?? []) { entry in
                        DiaryEntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.currentEntry = entry
                                navigateToDetailView(entry: entry)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    entryToDelete = entry
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                
                                Button {
                                    shareEntry(entry)
                                } label: {
                                    Label("分享", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    viewModel.toggleFavorite(entry)
                                } label: {
                                    Label(
                                        entry.isFavorite ? "取消收藏" : "收藏",
                                        systemImage: entry.isFavorite ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.yellow)
                            }
                            .listRowBackground(Color(UIColor.systemBackground))
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 4)
                    }
                }
                .listSectionSeparator(.hidden)
            }
            // 添加一个空白项来增加底部间距
            Text("")
                .frame(height: 60)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .opacity(listOpacity)
        .animation(.easeIn(duration: 0.3), value: refreshTrigger)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "note.text")
                .font(.system(size: 70))
                .foregroundColor(.blue.opacity(0.7))
            
            Text("还没有日记")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(
                showingSearchResults ? "没有找到符合条件的日记。\n尝试其他搜索词或清除筛选条件。" :
                "点击下方的加号按钮创建您的第一篇日记。"
            )
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            
            if showingSearchResults || selectedFilterTag != nil {
                Button {
                    searchText = ""
                    selectedFilterTag = nil
                    viewModel.loadEntries()
                    showingSearchResults = false
                } label: {
                    Text("清除所有筛选")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
                .padding(.top, 10)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private var addEntrySheet: some View {
        NavigationStack {
            CreateDiaryView(viewModel: viewModel, isPresented: $isAddingEntry)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("新建日记")
        }
    }
    
    private var filterSheet: some View {
        NavigationStack {
            VStack {
                List {
                    Section(header: Text("按日期排序")) {
                        ForEach(SortOption.allCases) { option in
                            Button {
                                selectedSortOption = option
                                sortEntries()
                                showingFilterSheet = false
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if selectedSortOption == option {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !allTags.isEmpty {
                        Section(header: Text("按标签筛选")) {
                            Button {
                                selectedFilterTag = nil
                                viewModel.loadEntries()
                                sortEntries()
                                showingFilterSheet = false
                            } label: {
                                HStack {
                                    Text("全部")
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if selectedFilterTag == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            ForEach(allTags, id: \.self) { tag in
                                Button {
                                    selectedFilterTag = tag
                                    viewModel.filterByTag(tag)
                                    sortEntries()
                                    showingFilterSheet = false
                                } label: {
                                    HStack {
                                        Text(tag)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if selectedFilterTag == tag {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            searchText = ""
                            selectedFilterTag = nil
                            selectedSortOption = .dateDesc
                            viewModel.loadEntries()
                            sortEntries()
                            showingFilterSheet = false
                            showingSearchResults = false
                        } label: {
                            HStack {
                                Spacer()
                                Text("重置所有筛选")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("筛选与排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showingFilterSheet = false
                    }
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func navigateToDetailView(entry: DiaryEntry) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            let hostingController = UIHostingController(rootView:
                NavigationStack {
                    DiaryDetailView(viewModel: viewModel, entry: entry)
                }
                .environmentObject(tabManager)
            )
            if let navigationController = rootViewController as? UINavigationController {
                navigationController.pushViewController(hostingController, animated: true)
            } else {
                rootViewController.present(hostingController, animated: true)
            }
        }
    }
    
    private func shareEntry(_ entry: DiaryEntry) {
        let content = """
        标题: \(entry.title)
        日期: \(formatDate(entry.creationDate))
        
        \(entry.content)
        
        #\(entry.tags.joined(separator: " #"))
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [content],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private func getDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private var groupedEntries: [String: [DiaryEntry]] {
        let groups = Dictionary(grouping: viewModel.entries) { entry in
            return getDateString(from: entry.creationDate)
        }
        return groups
    }
    
    private var allTags: [String] {
        var tags = Set<String>()
        for entry in viewModel.allEntries {
            for tag in entry.tags {
                tags.insert(tag)
            }
        }
        return Array(tags).sorted()
    }
    
    private func sortEntries() {
        switch selectedSortOption {
        case .dateDesc:
            viewModel.sortEntries { $0.creationDate > $1.creationDate }
        case .dateAsc:
            viewModel.sortEntries { $0.creationDate < $1.creationDate }
        case .titleAsc:
            viewModel.sortEntries { $0.title < $1.title }
        case .titleDesc:
            viewModel.sortEntries { $0.title > $1.title }
        }
        
        // 触发列表更新动画
        refreshTrigger.toggle()
    }
    
    private func refreshData() async {
        await viewModel.refreshData()
        // 触发列表刷新动画
        withAnimation {
            refreshTrigger.toggle()
        }
    }
}

// MARK: - 自定义日记条目行
struct DiaryEntryRow: View {
    let entry: DiaryEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // 标题
                Text(entry.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                // 收藏图标
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.footnote)
                }
                
                // 日期指示
                Text(formattedTime())
                        .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 内容预览
            Text(entry.content)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
            
            // 底部信息
            HStack(spacing: 8) {
                // 心情
                if let mood = entry.mood {
                    // 简化心情显示
                    Text(getMoodDisplayText(mood))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                
                // 标签
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        if entry.tags.count > 3 {
                            Text("+\(entry.tags.count - 3)")
                                .font(.caption)
                    .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(entry.isFavorite ? Color.yellow.opacity(0.05) : Color(UIColor.secondarySystemBackground))
                .shadow(color: Color.primary.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(entry.isFavorite ? Color.yellow.opacity(0.3) : Color.clear, lineWidth: entry.isFavorite ? 1 : 0)
        )
        .padding(.horizontal, 8)
    }
    
    private func formattedTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.creationDate)
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

// MARK: - 预览
#Preview {
    let viewModel = PreviewHelpers.createViewModel()
    
    DiaryListView(viewModel: viewModel)
        .environmentObject(PreviewHelpers.tabManager)
} 