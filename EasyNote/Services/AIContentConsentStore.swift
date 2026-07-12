import Foundation

protocol AIContentConsentProviding {
    var isGranted: Bool { get }
    func grant()
    func revoke()
}

enum AIContentConsentPolicy {
    static let defaultsKey = "ai_content_consent_granted"
    static let requiredMessage = "请先在设置中阅读并允许将日记、转写文本或推荐所需的近期日记发送给 DeepSeek。"
    static let disclosure = "使用 AI 功能时，EasyNote 会将你选择处理的日记或语音转写文本发送给 DeepSeek；生成个性化推荐时，还会发送用于分析的近期日记标题、正文、心情和标签。录音音频文件和 API 密钥不会作为 AI 内容发送；API 密钥仅在 Authorization 请求头中用于鉴权。"
}

final class AIContentConsentStore: AIContentConsentProviding {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isGranted: Bool {
        userDefaults.bool(forKey: AIContentConsentPolicy.defaultsKey)
    }

    func grant() {
        userDefaults.set(true, forKey: AIContentConsentPolicy.defaultsKey)
    }

    func revoke() {
        userDefaults.set(false, forKey: AIContentConsentPolicy.defaultsKey)
    }
}
