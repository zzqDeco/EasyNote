import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var themeManager: ThemeManager

    private let dependencies: SettingsDependencies

    init(
        themeManager: ThemeManager,
        dependencies: SettingsDependencies = SettingsDependencies()
    ) {
        self._themeManager = ObservedObject(wrappedValue: themeManager)
        self.dependencies = dependencies
    }

    var body: some View {
        NavigationView {
            Form {
                AppearanceSettingsSection(themeManager: themeManager)
                AISettingsSection()
                ReminderSettingsSection(
                    modelContext: modelContext,
                    scenePhase: scenePhase,
                    dependencies: dependencies
                )
                BackupSettingsSection(
                    modelContext: modelContext,
                    backupService: dependencies.backupService
                )
                SyncSettingsSection(report: dependencies.cloudKitPreflightReport)

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
        .modelContainer(for: [DiaryEntry.self, TodoItem.self, ChatSession.self, SessionMessage.self], inMemory: true)
}
