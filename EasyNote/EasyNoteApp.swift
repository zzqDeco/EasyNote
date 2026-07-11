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
import OSLog

@main
struct EasyNoteApp: App {
    private static let logger = Logger(subsystem: "EasyNote", category: "AppLifecycle")
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
                    Self.logger.info("Application launched")
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // 应用进入前台时
                Self.logger.debug("Application became active")
            } else if newPhase == .inactive {
                // 应用进入非活动状态时
                Self.logger.debug("Application became inactive")
            } else if newPhase == .background {
                // 应用进入后台时，确保数据保存
                Self.logger.debug("Application entered background")
                guard let modelContainer = persistenceBootstrap.modelContainer else {
                    return
                }
                do {
                    try modelContainer.mainContext.save()
                    Self.logger.debug("Background persistence save completed")
                } catch {
                    Self.logger.error("Background persistence save failed")
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
