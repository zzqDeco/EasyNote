import Foundation

struct DiaryReviewProjection {
    struct WindowSummary: Equatable, Identifiable {
        enum Kind: String, CaseIterable, Identifiable {
            case recent7Days = "最近7天"
            case recent30Days = "最近30天"
            case currentMonth = "本月"

            var id: String { rawValue }
        }

        let kind: Kind
        let entryCount: Int
        let favoriteCount: Int
        let startDate: Date
        let endDate: Date

        var id: String { kind.id }
    }

    struct MonthlySummary: Equatable, Identifiable {
        let monthStart: Date
        let entryCount: Int
        let favoriteCount: Int
        let moodDistribution: [MoodCount]
        let topTags: [TagCount]

        var id: Date { monthStart }
    }

    struct TagCount: Equatable, Identifiable {
        let tag: String
        let count: Int

        var id: String { tag }
    }

    struct MoodCount: Equatable, Identifiable {
        let mood: String
        let count: Int

        var id: String { mood }
    }

    let totalEntryCount: Int
    let totalFavoriteCount: Int
    let monthlySummaries: [MonthlySummary]
    let windowSummaries: [WindowSummary]
    let overallTopTags: [TagCount]
    let overallMoodDistribution: [MoodCount]
    let recentFavorites: [DiaryEntry]

    static func build(
        from entries: [DiaryEntry],
        calendar: Calendar = .current,
        now: Date = Date(),
        topLimit: Int = 5,
        recentFavoriteLimit: Int = 5
    ) -> DiaryReviewProjection {
        let sortedEntries = entries.sorted(by: entrySort)
        let monthlySummaries = monthlyGroups(
            from: entries,
            calendar: calendar,
            topLimit: topLimit
        )
        let windows = WindowSummary.Kind.allCases.map {
            windowSummary(for: $0, entries: entries, calendar: calendar, now: now)
        }

        return DiaryReviewProjection(
            totalEntryCount: entries.count,
            totalFavoriteCount: entries.filter(\.isFavorite).count,
            monthlySummaries: monthlySummaries,
            windowSummaries: windows,
            overallTopTags: topTags(from: entries, limit: topLimit),
            overallMoodDistribution: moodDistribution(from: entries),
            recentFavorites: Array(sortedEntries.filter(\.isFavorite).prefix(recentFavoriteLimit))
        )
    }

    static func entries(
        for kind: WindowSummary.Kind,
        in entries: [DiaryEntry],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [DiaryEntry] {
        let bounds = windowBounds(for: kind, calendar: calendar, now: now)
        return entries.filter { entry in
            entry.creationDate >= bounds.start && entry.creationDate < bounds.end
        }
    }

    private static func monthlyGroups(
        from entries: [DiaryEntry],
        calendar: Calendar,
        topLimit: Int
    ) -> [MonthlySummary] {
        let grouped = Dictionary(grouping: entries) { entry in
            monthStart(for: entry.creationDate, calendar: calendar)
        }

        return grouped.map { monthStart, monthEntries in
            MonthlySummary(
                monthStart: monthStart,
                entryCount: monthEntries.count,
                favoriteCount: monthEntries.filter(\.isFavorite).count,
                moodDistribution: moodDistribution(from: monthEntries),
                topTags: topTags(from: monthEntries, limit: topLimit)
            )
        }
        .sorted { lhs, rhs in
            lhs.monthStart > rhs.monthStart
        }
    }

    private static func windowSummary(
        for kind: WindowSummary.Kind,
        entries: [DiaryEntry],
        calendar: Calendar,
        now: Date
    ) -> WindowSummary {
        let bounds = windowBounds(for: kind, calendar: calendar, now: now)
        let windowEntries = entries.filter { entry in
            entry.creationDate >= bounds.start && entry.creationDate < bounds.end
        }

        return WindowSummary(
            kind: kind,
            entryCount: windowEntries.count,
            favoriteCount: windowEntries.filter(\.isFavorite).count,
            startDate: bounds.start,
            endDate: bounds.end
        )
    }

    private static func windowBounds(
        for kind: WindowSummary.Kind,
        calendar: Calendar,
        now: Date
    ) -> (start: Date, end: Date) {
        let todayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now

        switch kind {
        case .recent7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return (start, end)
        case .recent30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            return (start, end)
        case .currentMonth:
            let components = calendar.dateComponents([.year, .month], from: todayStart)
            let start = calendar.date(from: components) ?? todayStart
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: start) ?? end
            return (start, monthEnd)
        }
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static func topTags(from entries: [DiaryEntry], limit: Int) -> [TagCount] {
        let counts = entries
            .flatMap(\.tags)
            .reduce(into: [String: Int]()) { result, tag in
                result[tag, default: 0] += 1
            }

        return counts.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.tag.localizedStandardCompare(rhs.tag) == .orderedAscending
                }
                return lhs.count > rhs.count
            }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    private static func moodDistribution(from entries: [DiaryEntry]) -> [MoodCount] {
        let counts = entries
            .compactMap(\.mood)
            .reduce(into: [String: Int]()) { result, mood in
                result[mood, default: 0] += 1
            }

        return counts.map { MoodCount(mood: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.mood.localizedStandardCompare(rhs.mood) == .orderedAscending
                }
                return lhs.count > rhs.count
            }
    }

    private static func entrySort(_ lhs: DiaryEntry, _ rhs: DiaryEntry) -> Bool {
        if lhs.creationDate == rhs.creationDate {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.creationDate > rhs.creationDate
    }
}
