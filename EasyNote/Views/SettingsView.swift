import SwiftUI

struct SettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @AppStorage("openai_api_key") private var apiKey = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("外观")) {
                    Toggle("深色模式", isOn: Binding(
                        get: { themeManager.colorScheme == .dark },
                        set: { _ in themeManager.toggleDarkMode() }
                    ))
                    
                    Picker("主题颜色", selection: Binding(
                        get: { themeManager.accentColorName },
                        set: { themeManager.setAccentColor($0) }
                    )) {
                        Text("蓝色").tag("blue")
                        Text("绿色").tag("green")
                        Text("紫色").tag("purple")
                        Text("红色").tag("red")
                        Text("橙色").tag("orange")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section(header: Text("AI")) {
                    SecureField("DeepSeek API密钥", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    if !apiKey.isEmpty {
                        Button("清除API密钥", role: .destructive) {
                            apiKey = ""
                        }
                    }
                } footer: {
                    Text("API密钥仅保存在本机UserDefaults中，仓库不包含默认密钥。")
                }
                
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
                
                Section {
                    Color.clear
                        .frame(height: 60)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("设置")
        }
    }
}

#Preview {
    SettingsView(themeManager: ThemeManager())
} 
