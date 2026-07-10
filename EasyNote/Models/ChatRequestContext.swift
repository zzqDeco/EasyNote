import Foundation

struct ChatConversationMessageSnapshot: Equatable, Sendable {
    let content: String
    let isUser: Bool

    init(content: String, isUser: Bool) {
        self.content = content
        self.isUser = isUser
    }

    init(message: SessionMessage) {
        self.init(content: message.content, isUser: message.isUser)
    }
}

struct ChatDiaryEntrySnapshot: Equatable, Sendable {
    let id: UUID
    let title: String
    let content: String
    let mood: String?
    let tags: [String]
    let creationDate: Date

    init(
        id: UUID,
        title: String,
        content: String,
        mood: String?,
        tags: [String],
        creationDate: Date
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.mood = mood
        self.tags = tags
        self.creationDate = creationDate
    }

    init(entry: DiaryEntry) {
        self.init(
            id: entry.id,
            title: entry.title,
            content: entry.content,
            mood: entry.mood,
            tags: entry.tags,
            creationDate: entry.creationDate
        )
    }
}

struct ChatRequestContext: Equatable, Sendable {
    let requestID: UUID
    let sessionID: UUID
    let userQuery: String
    let relatedEntryIDs: [UUID]
    let conversationHistory: [ChatConversationMessageSnapshot]
    let diaryEntries: [ChatDiaryEntrySnapshot]

    func retrying(requestID: UUID = UUID()) -> ChatRequestContext {
        ChatRequestContext(
            requestID: requestID,
            sessionID: sessionID,
            userQuery: userQuery,
            relatedEntryIDs: relatedEntryIDs,
            conversationHistory: conversationHistory,
            diaryEntries: diaryEntries
        )
    }
}

struct ChatRequestFailure: Equatable, Identifiable, Sendable {
    let context: ChatRequestContext
    let message: String

    var id: UUID { context.requestID }
}

struct LocalDiaryQueryResult: Equatable, Sendable {
    let message: String
    let relatedEntryIDs: [UUID]
}

enum LocalDiaryQueryAnalyzer {
    private static let ignoredQueryFragments = [
        "我的", "笔记", "日记", "查找", "查看", "包含", "关于", "相关",
        "哪些", "什么", "请", "帮我", "一下", "记录", "提到过", "提到", "中"
    ]

    static func matchingEntries(
        for query: String,
        in entries: [ChatDiaryEntrySnapshot]
    ) -> [ChatDiaryEntrySnapshot] {
        let terms = searchTerms(from: query)
        guard !terms.isEmpty else { return [] }

        return entries.filter { entry in
            let searchableValues = [entry.title, entry.content] + entry.tags
            return terms.contains { term in
                searchableValues.contains { value in
                    value.localizedCaseInsensitiveContains(term)
                }
            }
        }
    }

    static func analyze(
        query: String,
        entries: [ChatDiaryEntrySnapshot]
    ) -> LocalDiaryQueryResult? {
        guard !entries.isEmpty else { return nil }

        if query.contains("最近") || query.contains("近期") {
            let recentEntries = Array(entries.sorted { $0.creationDate > $1.creationDate }.prefix(5))
            return LocalDiaryQueryResult(
                message: labeledMessage(
                    heading: "根据当前日记，最近的记录是：",
                    entries: recentEntries,
                    includesPreview: false
                ),
                relatedEntryIDs: recentEntries.map(\.id)
            )
        }

        if query.contains("心情") || query.contains("情绪") || query.contains("感受") {
            let moodCounts = entries.reduce(into: [String: Int]()) { counts, entry in
                guard let mood = entry.mood?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !mood.isEmpty else { return }
                counts[mood, default: 0] += 1
            }
            guard !moodCounts.isEmpty else { return nil }

            let lines = moodCounts
                .sorted { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
                }
                .map { "- \($0.key)：\($0.value) 条记录" }

            return LocalDiaryQueryResult(
                message: (["本地结果（AI 服务暂不可用）", "根据当前日记，记录到的心情有："] + lines)
                    .joined(separator: "\n"),
                relatedEntryIDs: entries.compactMap { entry in
                    guard let mood = entry.mood?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !mood.isEmpty else { return nil }
                    return entry.id
                }
            )
        }

        let matches = matchingEntries(for: query, in: entries)
        guard !matches.isEmpty else { return nil }

        let displayedMatches = Array(matches.prefix(5))
        return LocalDiaryQueryResult(
            message: labeledMessage(
                heading: "根据当前日记，找到 \(matches.count) 条匹配记录：",
                entries: displayedMatches,
                includesPreview: true
            ),
            relatedEntryIDs: matches.map(\.id)
        )
    }

    private static func searchTerms(from query: String) -> [String] {
        let normalized = query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let components = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        var candidates = components.filter { !$0.isEmpty }
        if !normalized.isEmpty {
            candidates.append(normalized)
        }

        let terms = candidates.compactMap { candidate -> String? in
            let reduced = ignoredQueryFragments.reduce(candidate) { partial, fragment in
                partial.replacingOccurrences(of: fragment, with: "")
            }
            let cleaned = reduced.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            return cleaned.count >= 2 ? cleaned : nil
        }

        return Array(Set(terms)).sorted()
    }

    private static func labeledMessage(
        heading: String,
        entries: [ChatDiaryEntrySnapshot],
        includesPreview: Bool
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = ["本地结果（AI 服务暂不可用）", heading]
        for (index, entry) in entries.enumerated() {
            lines.append("\(index + 1). 《\(entry.title)》（\(formatter.string(from: entry.creationDate))）")
            if includesPreview {
                let preview = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !preview.isEmpty {
                    lines.append("   \(String(preview.prefix(50)))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum ChatPromptBuilder {
    static func makePrompt(from context: ChatRequestContext) -> String {
        var prompt = "你是 EasyNote 的 AI 助手，只能根据提供的日记快照回答。"
        prompt += "\n\n用户的问题是：\"\(context.userQuery)\"\n"

        let recentHistory = context.conversationHistory.suffix(5)
        if !recentHistory.isEmpty {
            prompt += "\n对话历史：\n"
            for message in recentHistory {
                prompt += "\(message.isUser ? "用户" : "AI")：\(message.content)\n"
            }
        }

        let relatedIDSet = Set(context.relatedEntryIDs)
        let relatedEntries = context.diaryEntries.filter { relatedIDSet.contains($0.id) }
        let promptEntries = relatedEntries.isEmpty
            ? Array(context.diaryEntries.sorted { $0.creationDate > $1.creationDate }.prefix(3))
            : Array(relatedEntries.prefix(3))

        if promptEntries.isEmpty {
            prompt += "\n用户目前没有日记。\n"
        } else {
            prompt += relatedEntries.isEmpty
                ? "\n最近的日记快照（可能与问题无直接关联）：\n"
                : "\n相关日记快照：\n"
            for (index, entry) in promptEntries.enumerated() {
                prompt += "日记 \(index + 1) 标题：\(entry.title)\n"
                prompt += "内容：\(String(entry.content.prefix(100)))\n"
                if let mood = entry.mood, !mood.isEmpty {
                    prompt += "心情：\(mood)\n"
                }
                if !entry.tags.isEmpty {
                    prompt += "标签：\(entry.tags.joined(separator: ", "))\n"
                }
            }
        }

        prompt += "\n请明确区分日记事实与建议；不得补充快照中不存在的经历、情绪或关联。"
        return prompt
    }
}
