//
//  DiaryListView.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import SwiftUI
import SwiftData

struct DiaryListView: View {
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case entries = "列表"
        case review = "回顾"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: DiaryViewModel
    @EnvironmentObject private var tabManager: TabSelectionManager
    @State private var isAddingEntry = false
    @State private var showingDeleteConfirmation = false
    @State private var entryToDelete: DiaryEntry?
    @State private var scrollToTop = false
    @State private var showingFilterSheet = false
    @State private var selectedDisplayMode: DisplayMode = .entries
    @State private var persistenceError: String?
    
    // 用于动画的状态
    @State private var listOpacity = 0.0
    @State private var refreshTrigger = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主列表内容
                VStack(spacing: 0) {
                    displayModePicker

                    if let persistenceError {
                        Text(persistenceError)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                    }

                    if selectedDisplayMode == .review {
                        DiaryReviewView(entries: viewModel.allEntries)
                    } else {
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
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.entries.count)
                .animation(.easeInOut(duration: 0.3), value: viewModel.diaryQuery)
                .animation(.easeInOut(duration: 0.2), value: selectedDisplayMode)
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
                        let feedback = PersistenceFeedback.resolve(
                            succeeded: viewModel.deleteEntry(entry),
                            viewModelError: viewModel.errorMessage,
                            fallbackError: "删除日记失败，请重试"
                        )
                        persistenceError = feedback.errorMessage
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

    private var displayModePicker: some View {
        Picker("日记视图", selection: $selectedDisplayMode) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 10)
        .accessibilityIdentifier("diary.displayModeSegmentedControl")
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索日记...", text: searchTextBinding)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .accessibilityIdentifier("diary.searchField")
                .onSubmit {
                    refreshTrigger.toggle()
                }
            
            if !viewModel.diaryQuery.searchText.isEmpty {
                Button {
                    viewModel.searchEntries("")
                    refreshTrigger.toggle()
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
                    .background(hasActiveFilters ? Color.blue.opacity(0.18) : Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .accessibilityIdentifier("diary.filterButton")
                
                // 排序显示
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(viewModel.diaryQuery.sortOption.rawValue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)
                
                // 标签筛选显示
                if let tag = viewModel.diaryQuery.selectedTag {
                    HStack {
                        Text("标签: \(tag)")
                        Button {
                            viewModel.filterByTag(nil)
                            refreshTrigger.toggle()
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

                if let mood = viewModel.diaryQuery.selectedMood {
                    HStack {
                        Text("心情: \(moodDisplayText(mood))")
                        Button {
                            viewModel.filterByMood(nil)
                            refreshTrigger.toggle()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.teal.opacity(0.1))
                    .cornerRadius(12)
                }

                if viewModel.diaryQuery.favoriteOnly {
                    HStack {
                        Text("仅收藏")
                        Button {
                            viewModel.setFavoriteOnly(false)
                            refreshTrigger.toggle()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(12)
                }

                if viewModel.diaryQuery.startDate != nil || viewModel.diaryQuery.endDate != nil {
                    HStack {
                        Text(dateRangeLabel)
                        Button {
                            viewModel.setDateRange(start: nil, end: nil)
                            refreshTrigger.toggle()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.1))
                    .cornerRadius(12)
                }
                
                if hasSearchText {
                    HStack {
                        Text("搜索: \(viewModel.diaryQuery.searchText)")
                        Button {
                            viewModel.searchEntries("")
                            refreshTrigger.toggle()
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
            if viewModel.diaryQuery.sortOption == .dateDesc || viewModel.diaryQuery.sortOption == .dateAsc {
                ForEach(sortedGroupedDateKeys, id: \.self) { dateString in
                    Section(header: Text(dateString)) {
                        ForEach(groupedEntries[dateString] ?? []) { entry in
                            diaryRow(entry)
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            } else {
                ForEach(viewModel.entries) { entry in
                    diaryRow(entry)
                }
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
            
            Text(viewModel.allEntries.isEmpty ? "还没有日记" : "没有找到日记")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(
                hasActiveFilters ? "没有找到符合条件的日记。\n尝试其他搜索词或清除筛选条件。" :
                "点击下方的加号按钮创建您的第一篇日记。"
            )
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            
            if hasActiveFilters {
                Button {
                    resetAllFilters()
                } label: {
                    Text("清除所有筛选")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
                .accessibilityIdentifier("diary.clearFiltersButton")
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
                        ForEach(DiaryEntryQuery.SortOption.allCases) { option in
                            Button {
                                viewModel.sortEntries(by: option)
                                refreshTrigger.toggle()
                                showingFilterSheet = false
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if viewModel.diaryQuery.sortOption == option {
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
                                viewModel.filterByTag(nil)
                                refreshTrigger.toggle()
                                showingFilterSheet = false
                            } label: {
                                HStack {
                                    Text("全部")
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if viewModel.diaryQuery.selectedTag == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            ForEach(allTags, id: \.self) { tag in
                                Button {
                                    viewModel.filterByTag(tag)
                                    refreshTrigger.toggle()
                                    showingFilterSheet = false
                                } label: {
                                    HStack {
                                        Text(tag)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if viewModel.diaryQuery.selectedTag == tag {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !allMoods.isEmpty {
                        Section(header: Text("按心情筛选")) {
                            Button {
                                viewModel.filterByMood(nil)
                                refreshTrigger.toggle()
                                showingFilterSheet = false
                            } label: {
                                HStack {
                                    Text("全部")
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if viewModel.diaryQuery.selectedMood == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }

                            ForEach(allMoods, id: \.self) { mood in
                                Button {
                                    viewModel.filterByMood(mood)
                                    refreshTrigger.toggle()
                                    showingFilterSheet = false
                                } label: {
                                    HStack {
                                        Text(moodDisplayText(mood))
                                            .foregroundColor(.primary)

                                        Spacer()

                                        if viewModel.diaryQuery.selectedMood == mood {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text("收藏")) {
                        Toggle("仅显示收藏", isOn: favoriteOnlyBinding)
                    }

                    Section(header: Text("日期范围")) {
                        Toggle("开始日期", isOn: startDateEnabledBinding)

                        if viewModel.diaryQuery.startDate != nil {
                            DatePicker("从", selection: startDateBinding, displayedComponents: .date)
                        }

                        Toggle("结束日期", isOn: endDateEnabledBinding)

                        if viewModel.diaryQuery.endDate != nil {
                            DatePicker("到", selection: endDateBinding, displayedComponents: .date)
                        }
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            resetAllFilters()
                            showingFilterSheet = false
                        } label: {
                            HStack {
                                Spacer()
                                Text("重置所有筛选")
                                Spacer()
                            }
                        }
                        .accessibilityIdentifier("diary.clearFiltersButton")
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

    private func diaryRow(_ entry: DiaryEntry) -> some View {
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
                    if viewModel.toggleFavorite(entry) {
                        refreshTrigger.toggle()
                    }
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

    private var sortedGroupedDateKeys: [String] {
        groupedEntries.keys.sorted { lhs, rhs in
            viewModel.diaryQuery.sortOption == .dateDesc ? lhs > rhs : lhs < rhs
        }
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

    private var allMoods: [String] {
        Array(Set(viewModel.allEntries.compactMap { $0.mood })).sorted()
    }
    
    private var hasActiveFilters: Bool {
        viewModel.diaryQuery.hasActiveFilters
    }

    private var hasSearchText: Bool {
        !viewModel.diaryQuery.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dateRangeLabel: String {
        switch (viewModel.diaryQuery.startDate, viewModel.diaryQuery.endDate) {
        case let (start?, end?):
            return "\(shortDate(start)) - \(shortDate(end))"
        case let (start?, nil):
            return "从 \(shortDate(start))"
        case let (nil, end?):
            return "到 \(shortDate(end))"
        case (nil, nil):
            return ""
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.diaryQuery.searchText },
            set: { newValue in
                viewModel.searchEntries(newValue)
                refreshTrigger.toggle()
            }
        )
    }

    private var favoriteOnlyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.diaryQuery.favoriteOnly },
            set: { newValue in
                viewModel.setFavoriteOnly(newValue)
                refreshTrigger.toggle()
            }
        )
    }

    private var startDateEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.diaryQuery.startDate != nil },
            set: { enabled in
                let start = enabled ? (viewModel.diaryQuery.startDate ?? Date()) : nil
                viewModel.setDateRange(start: start, end: viewModel.diaryQuery.endDate)
                refreshTrigger.toggle()
            }
        )
    }

    private var endDateEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.diaryQuery.endDate != nil },
            set: { enabled in
                let end = enabled ? (viewModel.diaryQuery.endDate ?? Date()) : nil
                viewModel.setDateRange(start: viewModel.diaryQuery.startDate, end: end)
                refreshTrigger.toggle()
            }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.diaryQuery.startDate ?? Date() },
            set: { newValue in
                viewModel.setDateRange(start: newValue, end: viewModel.diaryQuery.endDate)
                refreshTrigger.toggle()
            }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.diaryQuery.endDate ?? Date() },
            set: { newValue in
                viewModel.setDateRange(start: viewModel.diaryQuery.startDate, end: newValue)
                refreshTrigger.toggle()
            }
        )
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private func moodDisplayText(_ mood: String) -> String {
        if let moodInt = Int(mood) {
            return MoodPickerView.moodText(for: moodInt)
        }
        return mood
    }

    private func resetAllFilters() {
        viewModel.resetDiaryQuery()
        refreshTrigger.toggle()
    }
    
    private func refreshData() async {
        await viewModel.refreshData()
        await MainActor.run {
            // 触发列表刷新动画
            withAnimation {
                refreshTrigger.toggle()
            }
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
