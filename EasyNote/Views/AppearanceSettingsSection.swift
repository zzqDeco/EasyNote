import SwiftUI

struct AppearanceSettingsSection: View {
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
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
    }
}
