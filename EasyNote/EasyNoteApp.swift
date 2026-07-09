//
//  EasyNoteApp.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation
import UIKit

@main
struct EasyNoteApp: App {
    // 添加应用生命周期状态对象
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if EasyNoteLaunchOptions.shouldDisableAnimations {
            UIView.setAnimationsEnabled(false)
        }

        if EasyNoteLaunchOptions.isUITesting {
            EasyNoteLaunchOptions.resetUserDefaultsForUITests()
        }
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DiaryEntry.self,
            TodoItem.self,
            ChatSession.self,
            SessionMessage.self
        ])
        
        let modelConfiguration: ModelConfiguration
        if EasyNoteLaunchOptions.isUITesting {
            modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            // 创建一个唯一的存储URL，确保数据保存在应用的Documents目录下
            let storeURL = URL.documentsDirectory.appending(path: "EasyNote.store")

            // 配置本地存储，避免 SwiftData 自动接管 CloudKit 同步
            modelConfiguration = ModelConfiguration(
                "EasyNote",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            print("SwiftData数据库路径: \(storeURL.path())")
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // 应用启动时执行的初始化逻辑
                    print("EasyNote应用启动")
                    
                    // 打印应用文档目录，以便定位SwiftData存储文件
                    print("应用文档目录: \(URL.documentsDirectory.path())")
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // 应用进入前台时
                print("应用激活")
            } else if newPhase == .inactive {
                // 应用进入非活动状态时
                print("应用进入非活动状态")
            } else if newPhase == .background {
                // 应用进入后台时，确保数据保存
                print("应用进入后台")
                do {
                    try sharedModelContainer.mainContext.save()
                    print("应用后台保存数据成功")
                } catch {
                    print("应用后台保存数据失败: \(error)")
                }
            }
        }
    }
}

private enum EasyNoteLaunchOptions {
    static let uiTestingArgument = "-easynote-ui-testing"
    static let disableAnimationsArgument = "-easynote-disable-animations"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
            || ProcessInfo.processInfo.environment["EASYNOTE_UI_TESTING"] == "1"
    }

    static var shouldDisableAnimations: Bool {
        ProcessInfo.processInfo.arguments.contains(disableAnimationsArgument)
    }

    static func resetUserDefaultsForUITests() {
        let defaults = UserDefaults.standard
        [
            "openai_api_key",
            "cached_recommendations",
            "recommendations_last_updated",
            "darkModeEnabled",
            "accentColorName",
            TodoReminderModeStore.modeDefaultsKey,
            LocalTodoNotificationService.enabledDefaultsKey
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}
