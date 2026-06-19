import Foundation

struct AIActionResult: Identifiable, Codable, Equatable {
    enum ActionType: String, CaseIterable, Codable {
        case summary
        case refine
        case expand
        case analyze
        case recommendation

        var displayName: String {
            switch self {
            case .summary:
                return "总结"
            case .refine:
                return "润色"
            case .expand:
                return "扩写"
            case .analyze:
                return "分析"
            case .recommendation:
                return "推荐"
            }
        }
    }

    enum ApplicationTarget: String, Codable, Hashable {
        case none
        case diarySummary
        case transcriptionText
        case recommendationList
    }

    let id: UUID
    let actionType: ActionType
    let applicationTarget: ApplicationTarget
    let sourceEntityId: UUID?
    let inputFingerprint: String
    let inputPreview: String
    let outputText: String
    let timestamp: Date
    let isSuccess: Bool
    let failureMessage: String?

    var canApply: Bool {
        isSuccess && !outputText.isEmpty && applicationTarget != .none && applicationTarget != .recommendationList
    }

    func matchesInput(_ input: String) -> Bool {
        inputFingerprint == Self.fingerprint(from: input)
    }

    static func success(
        actionType: ActionType,
        applicationTarget: ApplicationTarget,
        sourceEntityId: UUID? = nil,
        input: String,
        outputText: String,
        timestamp: Date = Date(),
        previewLimit: Int = 80
    ) -> AIActionResult {
        AIActionResult(
            id: UUID(),
            actionType: actionType,
            applicationTarget: applicationTarget,
            sourceEntityId: sourceEntityId,
            inputFingerprint: fingerprint(from: input),
            inputPreview: preview(from: input, limit: previewLimit),
            outputText: outputText,
            timestamp: timestamp,
            isSuccess: true,
            failureMessage: nil
        )
    }

    static func failure(
        actionType: ActionType,
        applicationTarget: ApplicationTarget,
        sourceEntityId: UUID? = nil,
        input: String,
        message: String,
        timestamp: Date = Date(),
        previewLimit: Int = 80
    ) -> AIActionResult {
        AIActionResult(
            id: UUID(),
            actionType: actionType,
            applicationTarget: applicationTarget,
            sourceEntityId: sourceEntityId,
            inputFingerprint: fingerprint(from: input),
            inputPreview: preview(from: input, limit: previewLimit),
            outputText: "",
            timestamp: timestamp,
            isSuccess: false,
            failureMessage: message
        )
    }

    private static func preview(from input: String, limit: Int) -> String {
        let normalized = input
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > limit else {
            return normalized
        }

        return "\(normalized.prefix(limit))..."
    }

    private static func fingerprint(from input: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
