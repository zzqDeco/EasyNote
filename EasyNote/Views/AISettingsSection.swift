import SwiftUI

struct AISettingsSection: View {
    @State private var apiKeyInput = ""
    @State private var isConfigured = false
    @State private var isConsentGranted = false
    @State private var feedbackMessage: String?
    @State private var errorMessage: String?
    @State private var showsConsentPrompt = false
    @State private var hasPresentedInitialConsentPrompt = false

    private let credentialStore: any CredentialStoreProviding
    private let consentStore: any AIContentConsentProviding

    init(
        credentialStore: any CredentialStoreProviding = KeychainCredentialStore(),
        consentStore: any AIContentConsentProviding = AIContentConsentStore()
    ) {
        self.credentialStore = credentialStore
        self.consentStore = consentStore
    }

    var body: some View {
        Section {
            SecureField("输入新的 DeepSeek API 密钥", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.apiKeyField")

            Button {
                saveAPIKey()
            } label: {
                Label("保存 API 密钥", systemImage: "key.fill")
            }
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("settings.saveApiKeyButton")

            Label(
                isConfigured ? "API 密钥已存入钥匙串" : "未配置 API 密钥",
                systemImage: isConfigured ? "checkmark.shield.fill" : "key.slash"
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if isConfigured {
                Button(role: .destructive) {
                    clearAPIKey()
                } label: {
                    Label("清除 API 密钥", systemImage: "trash")
                }
                .accessibilityIdentifier("settings.clearApiKeyButton")
            }

            Label(
                isConsentGranted ? "已允许发送所选文本" : "尚未允许发送所选文本",
                systemImage: isConsentGranted ? "checkmark.circle.fill" : "hand.raised.fill"
            )
            .font(.caption)
            .foregroundColor(isConsentGranted ? .green : .orange)

            if isConsentGranted {
                Button(role: .destructive) {
                    revokeConsent()
                } label: {
                    Label("撤回 AI 内容授权", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.revokeAIConsentButton")
            } else {
                Button {
                    showsConsentPrompt = true
                } label: {
                    Label("阅读并允许 AI 内容发送", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("settings.grantAIConsentButton")
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("settings.aiCredentialError")
            }
        } header: {
            Text("AI")
        } footer: {
            Text("密钥仅存储在本机钥匙串。只有明确授权后，所选日记或转写文本才会发送给 DeepSeek；录音音频文件和密钥不会作为 AI 内容发送，密钥仅在 Authorization 请求头中用于鉴权。")
        }
        .onAppear(perform: loadState)
        .alert("允许向 DeepSeek 发送内容？", isPresented: $showsConsentPrompt) {
            Button("取消", role: .cancel) {}
            Button("允许") {
                grantConsent()
            }
        } message: {
            Text(AIContentConsentPolicy.disclosure)
        }
    }

    private func loadState() {
        errorMessage = nil
        isConsentGranted = consentStore.isGranted

        do {
            let migrationResult = try credentialStore.migrateLegacyAPIKeyIfNeeded()
            isConfigured = try hasStoredAPIKey()
            if migrationResult == .migrated {
                feedbackMessage = "旧版 API 密钥已安全迁移到钥匙串。"
            }
            presentInitialConsentIfNeeded()
        } catch {
            isConfigured = (try? hasStoredAPIKey()) ?? false
            errorMessage = "API 密钥迁移或读取失败：\(error.localizedDescription)"
        }
    }

    private func saveAPIKey() {
        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        feedbackMessage = nil
        errorMessage = nil
        do {
            try credentialStore.saveAPIKey(apiKey)
            guard try credentialStore.readAPIKey() == apiKey else {
                throw CredentialStoreError.verificationFailed
            }
            apiKeyInput = ""
            isConfigured = true
            feedbackMessage = "API 密钥已保存到本机钥匙串。"
            if !isConsentGranted {
                hasPresentedInitialConsentPrompt = true
                showsConsentPrompt = true
            }
        } catch {
            errorMessage = "保存 API 密钥失败：\(error.localizedDescription)"
        }
    }

    private func clearAPIKey() {
        feedbackMessage = nil
        errorMessage = nil
        do {
            try credentialStore.deleteAPIKey()
            guard try credentialStore.readAPIKey() == nil else {
                throw CredentialStoreError.verificationFailed
            }
            apiKeyInput = ""
            isConfigured = false
            feedbackMessage = "API 密钥已从本机钥匙串清除。"
        } catch {
            errorMessage = "清除 API 密钥失败：\(error.localizedDescription)"
        }
    }

    private func grantConsent() {
        consentStore.grant()
        isConsentGranted = consentStore.isGranted
        feedbackMessage = "已允许将所选文本发送给 DeepSeek。"
        errorMessage = nil
    }

    private func revokeConsent() {
        consentStore.revoke()
        isConsentGranted = consentStore.isGranted
        feedbackMessage = "已撤回 AI 内容授权，后续请求将在本机被阻止。"
        errorMessage = nil
        hasPresentedInitialConsentPrompt = true
    }

    private func presentInitialConsentIfNeeded() {
        guard isConfigured,
              !isConsentGranted,
              !hasPresentedInitialConsentPrompt else {
            return
        }
        hasPresentedInitialConsentPrompt = true
        showsConsentPrompt = true
    }

    private func hasStoredAPIKey() throws -> Bool {
        guard let apiKey = try credentialStore.readAPIKey() else {
            return false
        }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
