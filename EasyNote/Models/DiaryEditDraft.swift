import Foundation

struct MoodOption: Equatable, Identifiable {
    let id: Int
    let emoji: String
    let label: String
    let systemImage: String
}

enum MoodCatalog {
    static let defaultIndex = 3

    static let options: [MoodOption] = [
        MoodOption(id: 1, emoji: "😢", label: "很糟", systemImage: "cloud.rain"),
        MoodOption(id: 2, emoji: "😔", label: "不好", systemImage: "cloud"),
        MoodOption(id: 3, emoji: "😐", label: "一般", systemImage: "sun.min"),
        MoodOption(id: 4, emoji: "😊", label: "不错", systemImage: "sun.max"),
        MoodOption(id: 5, emoji: "😁", label: "很棒", systemImage: "sun.max.fill"),
        MoodOption(id: 6, emoji: "😡", label: "愤怒", systemImage: "flame"),
        MoodOption(id: 7, emoji: "😱", label: "恐惧", systemImage: "exclamationmark.triangle"),
        MoodOption(id: 8, emoji: "😨", label: "焦虑", systemImage: "arrow.up.heart"),
        MoodOption(id: 9, emoji: "🤔", label: "思考", systemImage: "bubble.left.and.bubble.right"),
        MoodOption(id: 10, emoji: "😴", label: "疲倦", systemImage: "moon.zzz"),
        MoodOption(id: 11, emoji: "🥳", label: "兴奋", systemImage: "star.fill"),
        MoodOption(id: 12, emoji: "😂", label: "搞笑", systemImage: "face.smiling"),
        MoodOption(id: 13, emoji: "🥰", label: "爱意", systemImage: "heart.fill"),
        MoodOption(id: 14, emoji: "😇", label: "感恩", systemImage: "hands.sparkles"),
        MoodOption(id: 15, emoji: "😎", label: "自信", systemImage: "person.fill.checkmark"),
        MoodOption(id: 16, emoji: "😌", label: "放松", systemImage: "leaf")
    ]

    private static let legacyIndexes: [String: Int] = [
        "伤心": 1,
        "平静": 3,
        "开心": 5,
        "生气": 6,
        "惊讶": 11,
        "疲惫": 10
    ]

    private static let legacySystemImages: [String: String] = [
        "开心": "face.smiling",
        "平静": "face.dashed",
        "伤心": "face.sad",
        "生气": "face.angered",
        "惊讶": "face.surprised",
        "疲惫": "face.exhausted"
    ]

    static func storedLabel(for index: Int) -> String? {
        options.first { $0.id == index }?.label
    }

    static func displayText(for index: Int) -> String {
        guard let option = options.first(where: { $0.id == index }) else {
            return "未知心情"
        }
        return "\(option.label) \(option.emoji)"
    }

    static func index(forStoredLabel label: String?) -> Int? {
        guard let normalized = normalized(label) else { return nil }

        if let numericIndex = Int(normalized), storedLabel(for: numericIndex) != nil {
            return numericIndex
        }

        if let option = options.first(where: { $0.label == normalized }) {
            return option.id
        }

        return legacyIndexes[normalized]
    }

    static func canonicalStoredLabel(_ label: String?) -> String? {
        guard let normalized = normalized(label) else { return nil }

        if Int(normalized) != nil {
            return index(forStoredLabel: normalized).flatMap(storedLabel(for:))
                ?? storedLabel(for: defaultIndex)
        }

        return normalized
    }

    static func systemImage(forStoredLabel label: String?) -> String {
        if let normalized = normalized(label), let legacyImage = legacySystemImages[normalized] {
            return legacyImage
        }

        guard let index = index(forStoredLabel: label),
              let option = options.first(where: { $0.id == index }) else {
            return "sun.min"
        }
        return option.systemImage
    }

    private static func normalized(_ label: String?) -> String? {
        let value = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

struct DiaryEditDraft: Equatable {
    let entryID: UUID
    let originalContent: String
    let originalMood: String?
    let originalTags: [String]
    let originalAudioURL: URL?

    var content: String
    var mood: String?
    var tags: [String]
    var pendingReplacementAudioURL: URL?

    init(
        entryID: UUID,
        content: String,
        mood: String?,
        tags: [String],
        originalAudioURL: URL?,
        pendingReplacementAudioURL: URL? = nil
    ) {
        let canonicalMood = MoodCatalog.canonicalStoredLabel(mood)
        self.entryID = entryID
        self.originalContent = content
        self.originalMood = canonicalMood
        self.originalTags = tags
        self.originalAudioURL = originalAudioURL
        self.content = content
        self.mood = canonicalMood
        self.tags = tags
        self.pendingReplacementAudioURL = pendingReplacementAudioURL
    }

    var resolvedAudioURL: URL? {
        pendingReplacementAudioURL ?? originalAudioURL
    }

    var hasChanges: Bool {
        content != originalContent
            || MoodCatalog.canonicalStoredLabel(mood) != originalMood
            || tags != originalTags
            || pendingReplacementAudioURL != nil
    }

    @discardableResult
    mutating func replacePendingRecording(with replacement: URL?) -> URL? {
        guard let replacement else { return nil }

        let previousPending = pendingReplacementAudioURL
        if replacement.standardizedFileURL == originalAudioURL?.standardizedFileURL {
            pendingReplacementAudioURL = nil
        } else {
            pendingReplacementAudioURL = replacement
        }

        guard previousPending?.standardizedFileURL != pendingReplacementAudioURL?.standardizedFileURL,
              previousPending?.standardizedFileURL != originalAudioURL?.standardizedFileURL else {
            return nil
        }
        return previousPending
    }

    @discardableResult
    mutating func discardPendingRecording() -> URL? {
        defer { pendingReplacementAudioURL = nil }
        guard pendingReplacementAudioURL?.standardizedFileURL != originalAudioURL?.standardizedFileURL else {
            return nil
        }
        return pendingReplacementAudioURL
    }
}
