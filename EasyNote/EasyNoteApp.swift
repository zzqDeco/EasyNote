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

@main
struct EasyNoteApp: App {
    // 添加应用生命周期状态对象
    @Environment(\.scenePhase) private var scenePhase
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DiaryEntry.self,
            TodoItem.self,
            ChatSession.self,
            SessionMessage.self
        ])
        
        // 创建一个唯一的存储URL，确保数据保存在应用的Documents目录下
        let storeURL = URL.documentsDirectory.appending(path: "EasyNote.store")
        
        // 配置存储，明确指定URL和是否存储在内存中
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: nil,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: nil,
            readOnly: false
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("SwiftData数据库路径: \(storeURL.path())")
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
