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
    let userMessageWasSaved: Bool

    init(
        context: ChatRequestContext,
        message: String,
        userMessageWasSaved: Bool = true
    ) {
        self.context = context
        self.message = message
        self.userMessageWasSaved = userMessageWasSaved
    }

    var id: UUID { context.requestID }
}

struct LocalDiaryQueryResult: Equatable, Sendable {
    let message: String
    let relatedEntryIDs: [UUID]
}

enum LocalDiaryQueryAnalyzer {
    private static let ignoredQueryTerms: Set<String> = [
        "我的", "笔记", "日记", "查找", "查看", "包含", "关于", "相关",
        "哪些", "什么", "请", "帮我", "一下", "记录", "提到过", "提到", "中",
        "最近", "近期", "心情", "情绪", "感受"
    ]
    private static let queryPrefixes = [
        "我的笔记中提到过哪些", "我的日记中提到过哪些", "我的记录中提到过哪些",
        "笔记中提到过哪些", "日记中提到过哪些", "记录中提到过哪些",
        "我的笔记中提到过", "我的日记中提到过", "我的记录中提到过",
        "笔记中提到过", "日记中提到过", "记录中提到过",
        "最近写了哪些", "近期写了哪些", "我最近", "我近期", "请告诉我", "请帮我", "请查找", "请查看",
        "请包含", "帮我", "查找", "查看", "包含", "最近", "近期", "关于", "相关",
        "哪些", "什么", "我的"
    ]
    private static let querySuffixes = [
        "的心情怎么样", "的情绪怎么样", "的感受怎么样", "的心情如何", "的情绪如何", "的感受如何",
        "心情怎么样", "情绪怎么样", "感受怎么样", "心情如何", "情绪如何", "感受如何",
        "相关的心情", "相关的情绪", "相关的感受", "的日记中", "的记录中", "的笔记中",
        "日记中", "记录中", "笔记中", "的日记", "的记录", "的笔记", "的心情", "的情绪",
        "的感受", "提到过", "提到", "日记", "记录", "笔记", "心情", "情绪", "感受",
        "相关", "一下", "吗"
    ]

    static func matchingEntries(
        for query: String,
        in entries: [ChatDiaryEntrySnapshot]
    ) -> [ChatDiaryEntrySnapshot] {
        let terms = searchTerms(from: query)
        guard !terms.isEmpty else { return [] }

        return entries.filter { entry in
            return terms.contains { term in
                searchableValues(for: entry).contains { value in
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

        let topicTerms = topicSearchTerms(from: query)
        let topicEntries = matchingEntries(for: topicTerms, in: entries)
        let scopedEntries = topicTerms.isEmpty ? entries : topicEntries
        let isMoodQuery = query.contains("心情") || query.contains("情绪") || query.contains("感受")

        if (query.contains("最近") || query.contains("近期")), !isMoodQuery {
            guard !scopedEntries.isEmpty else { return nil }
            let recentEntries = Array(scopedEntries.sorted { $0.creationDate > $1.creationDate }.prefix(5))
            return LocalDiaryQueryResult(
                message: labeledMessage(
                    heading: "根据当前日记，最近的记录是：",
                    entries: recentEntries,
                    includesPreview: false
                ),
                relatedEntryIDs: recentEntries.map(\.id)
            )
        }

        if isMoodQuery {
            guard !scopedEntries.isEmpty else { return nil }
            let moodCounts = scopedEntries.reduce(into: [String: Int]()) { counts, entry in
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
                relatedEntryIDs: scopedEntries.compactMap { entry in
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

        let terms = candidates.flatMap { searchTerms(for: $0) }

        return Array(Set(terms)).sorted()
    }

    private static func topicSearchTerms(from query: String) -> [String] {
        let normalized = query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let candidates = components.filter { !$0.isEmpty } + (normalized.isEmpty ? [] : [normalized])
        let terms = candidates.compactMap(cleanedSearchTerm)
        return Array(Set(terms)).sorted()
    }

    private static func searchTerms(for candidate: String) -> [String] {
        let original = candidate.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard isUsableSearchTerm(original) else { return [] }
        guard let cleaned = cleanedSearchTerm(original), cleaned != original else {
            return [original]
        }
        return [original, cleaned]
    }

    private static func cleanedSearchTerm(_ candidate: String) -> String? {
        var term = candidate.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard isUsableSearchTerm(term) else { return nil }

        var changed = true
        var removedPrefix = false
        while changed {
            changed = false
            if let prefix = queryPrefixes.first(where: { term.hasPrefix($0) }) {
                term.removeFirst(prefix.count)
                changed = true
                removedPrefix = true
            }
            if removedPrefix, term.hasPrefix("的") {
                term.removeFirst()
                changed = true
            }
            if let suffix = querySuffixes.first(where: { term.hasSuffix($0) }) {
                term.removeLast(suffix.count)
                changed = true
            }
            term = term.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        }

        return isUsableSearchTerm(term) ? term : nil
    }

    private static func isUsableSearchTerm(_ term: String) -> Bool {
        guard !term.isEmpty, !ignoredQueryTerms.contains(term) else { return false }
        if term.count >= 2 { return true }
        return term.unicodeScalars.first?.properties.isIdeographic == true
    }

    private static func matchingEntries(
        for terms: [String],
        in entries: [ChatDiaryEntrySnapshot]
    ) -> [ChatDiaryEntrySnapshot] {
        guard !terms.isEmpty else { return [] }
        return entries.filter { entry in
            return terms.contains { term in
                searchableValues(for: entry).contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }
    }

    private static func searchableValues(for entry: ChatDiaryEntrySnapshot) -> [String] {
        [entry.title, entry.content] + entry.tags + [entry.mood].compactMap { mood in
            guard let mood = mood?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !mood.isEmpty else { return nil }
            return mood
        }
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
