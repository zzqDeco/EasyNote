import SwiftUI

struct DiaryReviewView: View {
    enum Section: String, CaseIterable, Identifiable {
        case monthly = "月度概览"
        case tags = "标签趋势"
        case moods = "心情分布"
        case favorites = "最近收藏"

        var id: String { rawValue }
    }

    let entries: [DiaryEntry]
    var calendar: Calendar = .current
    var now: Date = Date()

    @State private var selectedSection: Section = .monthly

    private var projection: DiaryReviewProjection {
        DiaryReviewProjection.build(from: entries, calendar: calendar, now: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("回顾视图", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 10)
            .accessibilityIdentifier("diary.reviewSegmentedControl")

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overviewStrip

                        switch selectedSection {
                        case .monthly:
                            monthlyOverview
                        case .tags:
                            tagTrends
                        case .moods:
                            moodDistribution
                        case .favorites:
                            recentFavorites
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 56))
                .foregroundColor(.blue.opacity(0.75))

            Text("还没有可回顾的日记")
                .font(.title3)
                .fontWeight(.medium)

            Text("创建几篇日记后，这里会显示月度数量、标签趋势、心情分布和最近收藏。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overviewStrip: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            metricTile(title: "日记", value: "\(projection.totalEntryCount)", systemImage: "doc.text")
            metricTile(title: "收藏", value: "\(projection.totalFavoriteCount)", systemImage: "star.fill")
            metricTile(title: "标签", value: "\(projection.overallTopTags.count)", systemImage: "tag")
        }
    }

    private var monthlyOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("固定窗口")

            VStack(spacing: 10) {
                ForEach(projection.windowSummaries) { summary in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary.kind.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("\(shortDate(summary.startDate)) - \(shortDate(calendar.date(byAdding: .day, value: -1, to: summary.endDate) ?? summary.endDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        countPair(primary: summary.entryCount, secondary: summary.favoriteCount)
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }

            sectionHeader("月度概览")

            if projection.monthlySummaries.isEmpty {
                secondaryEmpty("还没有月度数据")
            } else {
                VStack(spacing: 10) {
                    ForEach(projection.monthlySummaries.prefix(6)) { summary in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(monthTitle(summary.monthStart))
                                    .font(.headline)
                                Spacer()
                                countPair(primary: summary.entryCount, secondary: summary.favoriteCount)
                            }

                            if let firstMood = summary.moodDistribution.first {
                                Text("主要心情：\(moodDisplayText(firstMood.mood)) · \(firstMood.count) 次")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            tagLine(summary.topTags)
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var tagTrends: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("标签趋势")

            if projection.overallTopTags.isEmpty {
                secondaryEmpty("还没有标签")
            } else {
                rankedBars(
                    items: projection.overallTopTags,
                    maxCount: projection.overallTopTags.map(\.count).max() ?? 1,
                    title: { $0.tag },
                    count: { $0.count },
                    color: .green
                )
            }
        }
    }

    private var moodDistribution: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("心情分布")

            if projection.overallMoodDistribution.isEmpty {
                secondaryEmpty("还没有心情记录")
            } else {
                rankedBars(
                    items: projection.overallMoodDistribution,
                    maxCount: projection.overallMoodDistribution.map(\.count).max() ?? 1,
                    title: { moodDisplayText($0.mood) },
                    count: { $0.count },
                    color: .blue
                )
            }
        }
    }

    private var recentFavorites: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("最近收藏")

            if projection.recentFavorites.isEmpty {
                secondaryEmpty("还没有收藏日记")
            } else {
                VStack(spacing: 10) {
                    ForEach(projection.recentFavorites) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text(shortDate(entry.creationDate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if !entry.content.isEmpty {
                                Text(entry.content)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            tagLine(entry.tags.map { DiaryReviewProjection.TagCount(tag: $0, count: 1) })
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func metricTile(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundColor(.blue)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }

    private func secondaryEmpty(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
    }

    private func countPair(primary: Int, secondary: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(primary) 篇")
                .font(.headline)
            Text("\(secondary) 收藏")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func rankedBars<Item>(
        items: [Item],
        maxCount: Int,
        title: (Item) -> String,
        count: (Item) -> Int,
        color: Color
    ) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title(item))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(count(item))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { proxy in
                        let width = max(8, proxy.size.width * CGFloat(count(item)) / CGFloat(max(maxCount, 1)))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.28))
                            .frame(width: width)
                    }
                    .frame(height: 8)
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
    }

    private func tagLine(_ tags: [DiaryReviewProjection.TagCount]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags.prefix(5)) { tag in
                    Text(tag.count > 1 ? "\(tag.tag) \(tag.count)" : tag.tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                }
            }
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func moodDisplayText(_ mood: String) -> String {
        if let moodInt = Int(mood) {
            return MoodPickerView.moodText(for: moodInt)
        }
        return mood
    }
}

#Preview {
    DiaryReviewView(entries: [])
}
