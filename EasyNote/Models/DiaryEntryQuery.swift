import Foundation

struct DiaryEntryQuery: Equatable {
    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc = "最新优先"
        case dateAsc = "最早优先"
        case titleAsc = "标题升序"
        case titleDesc = "标题降序"

        var id: String { rawValue }
    }

    var searchText = ""
    var selectedTag: String?
    var selectedMood: String?
    var favoriteOnly = false
    var startDate: Date?
    var endDate: Date?
    var sortOption: SortOption = .dateDesc

    var hasActiveFilters: Bool {
        !normalizedSearchText.isEmpty ||
        selectedTag != nil ||
        selectedMood != nil ||
        favoriteOnly ||
        startDate != nil ||
        endDate != nil
    }

    func apply(to entries: [DiaryEntry], calendar: Calendar = .current) -> [DiaryEntry] {
        entries
            .filter { matches($0, calendar: calendar) }
            .sorted(by: sortComparator)
    }

    private func matches(_ entry: DiaryEntry, calendar: Calendar) -> Bool {
        if !normalizedSearchText.isEmpty && !matchesSearch(entry) {
            return false
        }

        if let selectedTag, !entry.tags.contains(selectedTag) {
            return false
        }

        if let selectedMood, entry.mood != selectedMood {
            return false
        }

        if favoriteOnly && !entry.isFavorite {
            return false
        }

        if let startDate, entry.creationDate < calendar.startOfDay(for: startDate) {
            return false
        }

        if let endDate,
           let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)),
           entry.creationDate >= startOfNextDay {
            return false
        }

        return true
    }

    private func matchesSearch(_ entry: DiaryEntry) -> Bool {
        entry.title.localizedCaseInsensitiveContains(normalizedSearchText) ||
        entry.content.localizedCaseInsensitiveContains(normalizedSearchText) ||
        entry.tags.contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sortComparator(_ lhs: DiaryEntry, _ rhs: DiaryEntry) -> Bool {
        switch sortOption {
        case .dateDesc:
            return lhs.creationDate == rhs.creationDate ? lhs.title < rhs.title : lhs.creationDate > rhs.creationDate
        case .dateAsc:
            return lhs.creationDate == rhs.creationDate ? lhs.title < rhs.title : lhs.creationDate < rhs.creationDate
        case .titleAsc:
            let titleCompare = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            return titleCompare == .orderedSame ? lhs.creationDate > rhs.creationDate : titleCompare == .orderedAscending
        case .titleDesc:
            let titleCompare = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            return titleCompare == .orderedSame ? lhs.creationDate > rhs.creationDate : titleCompare == .orderedDescending
        }
    }
}
