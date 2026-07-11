import SwiftUI

struct AISettingsSection: View {
    @AppStorage("openai_api_key") private var apiKey = ""

    var body: some View {
        Section {
            SecureField("DeepSeek API密钥", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.apiKeyField")

            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("未配置 API 密钥")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("API 密钥已配置")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !apiKey.isEmpty {
                Button("清除API密钥", role: .destructive) {
                    apiKey = ""
                }
                .accessibilityIdentifier("settings.clearApiKeyButton")
            }
        } header: {
            Text("AI")
        } footer: {
            Text("API密钥仅保存在本机UserDefaults中，仓库不包含默认密钥。")
        }
    }
}
