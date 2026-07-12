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
    @StateObject private var persistenceBootstrap: PersistenceBootstrap

    init() {
        if EasyNoteLaunchOptions.shouldDisableAnimations {
            UIView.setAnimationsEnabled(false)
        }

        if EasyNoteLaunchOptions.isUITesting {
            EasyNoteLaunchOptions.resetUserDefaultsForUITests()
        }

        _persistenceBootstrap = StateObject(wrappedValue: PersistenceBootstrap(
            isStoredInMemoryOnly: EasyNoteLaunchOptions.isUITesting
        ))
    }
    
    var body: some Scene {
        WindowGroup {
            PersistenceRootView(bootstrap: persistenceBootstrap)
                .onAppear {
                    // 应用启动时执行的初始化逻辑
                    print("EasyNote应用启动")
                    
                    // 打印应用文档目录，以便定位SwiftData存储文件
                    print("应用文档目录: \(URL.documentsDirectory.path())")
                }
        }
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
                guard let modelContainer = persistenceBootstrap.modelContainer else {
                    return
                }
                do {
                    try modelContainer.mainContext.save()
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
            AIContentConsentPolicy.defaultsKey,
            "cached_recommendations",
            "recommendations_last_updated",
            "darkModeEnabled",
            "accentColorName",
            TodoReminderModeStore.modeDefaultsKey,
            TodoReminderModeStore.systemRemindersMayExistDefaultsKey,
            LocalTodoNotificationService.enabledDefaultsKey
        ].forEach { defaults.removeObject(forKey: $0) }
        _ = try? KeychainCredentialStore().deleteAPIKey()
    }
}
