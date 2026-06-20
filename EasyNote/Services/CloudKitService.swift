//
//  CloudKitService.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import Foundation
import CloudKit
import Combine
import SwiftUI

enum CloudKitError: Error {
    case recordNotFound
    case operationFailed(Error)
    case invalidRecord
    case unknownError
}

enum CloudKitStatus {
    case available
    case restricted
    case noAccount
    case temporarilyUnavailable
    case unknown
}

#if DEBUG
// 预览环境使用的简化版CloudKitService
class CloudKitServicePreview: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    
    init() {
        print("CloudKitServicePreview: 初始化完成")
    }
    
    func saveAudioFile(data: Data, fileName: String) -> AnyPublisher<URL, CloudKitError> {
        print("CloudKitServicePreview: 模拟保存音频文件")
        let subject = PassthroughSubject<URL, CloudKitError>()
        
        // 在预览环境中，我们只是简单地返回一个假URL
        DispatchQueue.main.async {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            subject.send(tempURL)
            subject.send(completion: .finished)
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    func fetchAudioFile(recordName: String) -> AnyPublisher<URL, CloudKitError> {
        print("CloudKitServicePreview: 模拟获取音频文件")
        let subject = PassthroughSubject<URL, CloudKitError>()
        
        // 在预览环境中，我们只是简单地返回一个假URL
        DispatchQueue.main.async {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("previewAudio.m4a")
            subject.send(tempURL)
            subject.send(completion: .finished)
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    func syncDiaryEntries(entries: [DiaryEntry]) -> AnyPublisher<Void, Error> {
        print("CloudKitServicePreview: 模拟同步日记条目")
        let subject = PassthroughSubject<Void, Error>()
        
        DispatchQueue.main.async {
            // 在预览环境中，我们什么也不做，只是返回成功
            subject.send(())
            subject.send(completion: .finished)
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    func fetchDiaryEntries() -> AnyPublisher<[DiaryEntry], Error> {
        print("CloudKitServicePreview: 模拟获取日记条目")
        let subject = PassthroughSubject<[DiaryEntry], Error>()
        
        DispatchQueue.main.async {
            // 在预览环境中，我们返回一个空数组
            subject.send([])
            subject.send(completion: .finished)
        }
        
        return subject.eraseToAnyPublisher()
    }
}

// 工厂方法创建合适的服务实例
func createCloudKitService() -> any ObservableObject {
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
        print("使用预览版CloudKitService")
        return CloudKitServicePreview()
    } else {
        return CloudKitService(containerIdentifier: CloudKitSyncPreflight.defaultContainerIdentifier)
    }
}
#endif

class CloudKitService: ObservableObject {
    static let shared = CloudKitService()
    
    @Published var cloudKitStatus: CloudKitStatus = .unknown
    @Published var isCheckingStatus = false
    @Published var errorMessage: String?
    
    private var container: CKContainer?
    private var privateDatabase: CKDatabase?
    private var isSimulationMode: Bool = false
    
    @Published var isSyncing = false {
        didSet {
            // 发送同步状态变化通知
            NotificationCenter.default.post(name: Notification.Name("CloudKitSyncStatusChanged"), object: isSyncing)
        }
    }
    @Published var lastSyncDate: Date?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(containerIdentifier: String = CloudKitSyncPreflight.defaultContainerIdentifier) {
        // 在初始化时检测是否应该使用模拟模式（适用于免费开发者账号）
        #if DEBUG
        // 调试模式下，默认使用模拟模式
        isSimulationMode = true
        print("CloudKitService: 使用模拟模式（适用于免费开发者账号）")
        self.cloudKitStatus = .temporarilyUnavailable
        self.errorMessage = "免费开发者账号不支持iCloud功能"
        #else
        do {
            self.container = CKContainer(identifier: containerIdentifier)
            self.privateDatabase = container?.privateCloudDatabase
        } catch {
            print("CloudKit初始化失败，切换到模拟模式: \(error.localizedDescription)")
            isSimulationMode = true
            self.cloudKitStatus = .temporarilyUnavailable
            self.errorMessage = "iCloud初始化失败，使用本地存储模式"
        }
        #endif
    }
    
    // 检查iCloud账户状态
    func checkAccountStatus() {
        isCheckingStatus = true
        errorMessage = nil
        
        if isSimulationMode {
            DispatchQueue.main.async {
                self.isCheckingStatus = false
                self.cloudKitStatus = .noAccount
                self.errorMessage = "免费开发者账号不支持iCloud功能，使用本地存储模式"
                print("CloudKitService: 模拟模式 - iCloud不可用")
            }
            return
        }
        
        container?.accountStatus { [weak self] (status, error) in
            DispatchQueue.main.async {
                self?.isCheckingStatus = false
                
                if let error = error {
                    self?.errorMessage = "检查iCloud状态失败: \(error.localizedDescription)"
                    self?.cloudKitStatus = .unknown
                    return
                }
                
                switch status {
                case .available:
                    self?.cloudKitStatus = .available
                    print("iCloud可用")
                case .restricted:
                    self?.cloudKitStatus = .restricted
                    self?.errorMessage = "您的iCloud账户受到限制，无法使用同步功能"
                    print("iCloud受限")
                case .noAccount:
                    self?.cloudKitStatus = .noAccount
                    self?.errorMessage = "请在设置中登录您的iCloud账户以启用同步"
                    print("无iCloud账户")
                case .couldNotDetermine:
                    self?.cloudKitStatus = .unknown
                    self?.errorMessage = "无法确定iCloud账户状态"
                    print("无法确定iCloud状态")
                case .temporarilyUnavailable:
                    self?.cloudKitStatus = .temporarilyUnavailable
                    self?.errorMessage = "iCloud暂时不可用，请稍后再试"
                    print("iCloud暂时不可用")
                @unknown default:
                    self?.cloudKitStatus = .unknown
                    self?.errorMessage = "未知的iCloud账户状态"
                    print("未知iCloud状态")
                }
            }
        }
    }
    
    // 测试iCloud容器连接
    func testCloudKitConnection() -> AnyPublisher<Bool, Error> {
        if isSimulationMode {
            return Just(false)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        return Future<Bool, Error> { promise in
            let container = self.container
            let publicDB = container?.publicCloudDatabase
            
            // 创建测试记录类型
            let recordID = CKRecord.ID(recordName: "TestConnection")
            let record = CKRecord(recordType: "TestConnection", recordID: recordID)
            record["testField"] = "测试连接" as CKRecordValue
            
            // 尝试保存记录
            publicDB?.save(record) { (savedRecord, error) in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                // 保存成功，尝试删除测试记录
                if let savedRecord = savedRecord {
                    publicDB?.delete(withRecordID: savedRecord.recordID) { (_, deleteError) in
                        if let deleteError = deleteError {
                            // 删除失败但连接测试已成功
                            print("删除测试记录失败: \(deleteError.localizedDescription)")
                        }
                        
                        // 无论删除是否成功，连接测试已通过
                        promise(.success(true))
                    }
                } else {
                    // 保存成功但无记录返回，仍视为连接成功
                    promise(.success(true))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // 获取iCloud用户ID
    func fetchUserID() -> AnyPublisher<String, Error> {
        if isSimulationMode {
            return Just("simulation-user-id")
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        return Future<String, Error> { promise in
            self.container?.fetchUserRecordID { recordID, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                if let recordID = recordID {
                    promise(.success(recordID.recordName))
                } else {
                    promise(.failure(NSError(domain: "CloudKitService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取用户ID"])))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // 获取iCloud存储状态
    func fetchQuotaStatus() -> AnyPublisher<(Double, Double), Error> {
        if isSimulationMode {
            return Just((0.0, 5.0)) // 模拟0GB已用，5GB总容量
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        return Future<(Double, Double), Error> { promise in
            CKContainer.default().fetchUserRecordID { recordID, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                if let recordID = recordID {
                    print("成功获取用户ID：\(recordID.recordName)")
                    promise(.success((0, 0))) // 实际上CloudKit API不提供直接获取配额的方法
                } else {
                    promise(.failure(NSError(domain: "CloudKitService", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法获取用户iCloud存储配额"])))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // 保存录音文件到iCloud
    func saveAudioFile(data: Data, fileName: String) -> AnyPublisher<URL, CloudKitError> {
        let subject = PassthroughSubject<URL, CloudKitError>()
        
        if isSimulationMode {
            // 在模拟模式下，保存到本地文件系统
            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            
            do {
                try data.write(to: fileURL)
                subject.send(fileURL)
                subject.send(completion: .finished)
            } catch {
                subject.send(completion: .failure(.operationFailed(error)))
            }
            
            return subject.eraseToAnyPublisher()
        }
        
        // 创建临时文件
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: tempURL)
        } catch {
            return Fail(error: CloudKitError.operationFailed(error)).eraseToAnyPublisher()
        }
        
        // 创建资源
        let asset = CKAsset(fileURL: tempURL)
        
        // 创建记录
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: "AudioRecording", recordID: recordID)
        record["audioFile"] = asset
        record["fileName"] = fileName
        record["creationDate"] = Date()
        
        // 保存记录
        self.isSyncing = true
        
        privateDatabase?.save(record) { savedRecord, error in
            DispatchQueue.main.async {
                self.isSyncing = false
                
                if let error = error {
                    subject.send(completion: .failure(.operationFailed(error)))
                    return
                }
                
                guard let savedRecord = savedRecord,
                      let asset = savedRecord["audioFile"] as? CKAsset,
                      let fileURL = asset.fileURL else {
                    subject.send(completion: .failure(.invalidRecord))
                    return
                }
                
                // 创建永久URL
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let permanentURL = documentsDirectory.appendingPathComponent(fileName)
                
                do {
                    if FileManager.default.fileExists(atPath: permanentURL.path) {
                        try FileManager.default.removeItem(at: permanentURL)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: permanentURL)
                    subject.send(permanentURL)
                    subject.send(completion: .finished)
                } catch {
                    subject.send(completion: .failure(.operationFailed(error)))
                }
                
                // 清理临时文件
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    // 从iCloud获取录音文件
    func fetchAudioFile(recordName: String) -> AnyPublisher<URL, CloudKitError> {
        let subject = PassthroughSubject<URL, CloudKitError>()
        
        if isSimulationMode {
            // 在模拟模式下，从本地文件系统获取
            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsDirectory.appendingPathComponent(recordName)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                subject.send(fileURL)
                subject.send(completion: .finished)
            } else {
                subject.send(completion: .failure(.recordNotFound))
            }
            
            return subject.eraseToAnyPublisher()
        }
        
        let recordID = CKRecord.ID(recordName: recordName)
        
        self.isSyncing = true
        
        privateDatabase?.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                self.isSyncing = false
                
                if let error = error {
                    subject.send(completion: .failure(.operationFailed(error)))
                    return
                }
                
                guard let record = record,
                      let asset = record["audioFile"] as? CKAsset,
                      let fileURL = asset.fileURL,
                      let fileName = record["fileName"] as? String else {
                    subject.send(completion: .failure(.invalidRecord))
                    return
                }
                
                // 创建永久URL
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let permanentURL = documentsDirectory.appendingPathComponent(fileName)
                
                do {
                    if FileManager.default.fileExists(atPath: permanentURL.path) {
                        try FileManager.default.removeItem(at: permanentURL)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: permanentURL)
                    subject.send(permanentURL)
                    subject.send(completion: .finished)
                } catch {
                    subject.send(completion: .failure(.operationFailed(error)))
                }
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    // 同步本地数据到iCloud
    func syncDiaryEntries(entries: [DiaryEntry]) -> AnyPublisher<Void, Error> {
        let subject = PassthroughSubject<Void, Error>()
        
        self.isSyncing = true
        
        let operations = entries.map { entry -> CKModifyRecordsOperation in
            let recordID = CKRecord.ID(recordName: entry.id.uuidString)
            let record = CKRecord(recordType: "DiaryEntry", recordID: recordID)
            
            record["title"] = entry.title
            record["content"] = entry.content
            record["creationDate"] = entry.creationDate
            record["mood"] = entry.mood
            record["aiSummary"] = entry.aiSummary
            record["tags"] = entry.tags as CKRecordValue
            
            if let audioURL = entry.audioURL {
                let asset = CKAsset(fileURL: audioURL)
                record["audioFile"] = asset
            }
            
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.qualityOfService = .userInitiated
            
            return operation
        }
        
        // 使用DispatchGroup来追踪所有操作完成
        let group = DispatchGroup()
        
        // 添加和跟踪所有操作
        for operation in operations {
            group.enter()
            operation.completionBlock = {
                group.leave()
            }
            privateDatabase?.add(operation)
        }
        
        // 如果没有操作，直接标记为完成
        if operations.isEmpty {
            group.enter()
            group.leave()
        }
        
        // 所有操作完成后通知
        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                subject.send(completion: .finished)
                return
            }
            
            self.isSyncing = false
            self.lastSyncDate = Date()
            subject.send(())
            subject.send(completion: .finished)
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    // 从iCloud获取日记条目
    func fetchDiaryEntries() -> AnyPublisher<[DiaryEntry], Error> {
        let subject = PassthroughSubject<[DiaryEntry], Error>()
        
        self.isSyncing = true
        
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "DiaryEntry", predicate: predicate)
        
        // 使用更新的API
        privateDatabase?.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 50) { result in
            DispatchQueue.main.async {
                self.isSyncing = false
                
                switch result {
                case .success(let matchResults):
                    // 处理结果
                    let recordMatchResults = matchResults.matchResults.compactMap { $0.1 }
                    
                    var entries: [DiaryEntry] = []
                    
                    for recordResult in recordMatchResults {
                        do {
                            let record = try recordResult.get()
                            
                            guard let title = record["title"] as? String,
                                  let content = record["content"] as? String,
                                  let creationDate = record["creationDate"] as? Date else {
                                continue
                            }
                            
                            let mood = record["mood"] as? String
                            let aiSummary = record["aiSummary"] as? String
                            let tags = record["tags"] as? [String] ?? []
                            
                            var audioURL: URL? = nil
                            if let asset = record["audioFile"] as? CKAsset, let fileURL = asset.fileURL {
                                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                let fileName = fileURL.lastPathComponent
                                audioURL = documentsDirectory.appendingPathComponent(fileName)
                                
                                do {
                                    if FileManager.default.fileExists(atPath: audioURL!.path) {
                                        try FileManager.default.removeItem(at: audioURL!)
                                    }
                                    try FileManager.default.copyItem(at: fileURL, to: audioURL!)
                                } catch {
                                    print("Error copying audio file: \(error)")
                                    audioURL = nil
                                }
                            }
                            
                            let entry = DiaryEntry(id: UUID(), title: title, content: content, mood: mood, tags: tags)
                            entry.audioURL = audioURL
                            entry.creationDate = creationDate
                            entry.aiSummary = aiSummary
                            
                            entries.append(entry)
                        } catch {
                            print("Error processing record: \(error)")
                        }
                    }
                    
                    subject.send(entries)
                    subject.send(completion: .finished)
                    self.lastSyncDate = Date()
                    
                case .failure(let error):
                    subject.send(completion: .failure(CloudKitError.operationFailed(error)))
                }
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
}

extension CloudKitService: CloudKitDiarySyncProviding {}

// SwiftUI视图扩展，用于显示iCloud状态
struct CloudKitStatusView: View {
    @ObservedObject private var cloudKitService = CloudKitService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                
                Text(statusText)
                    .font(.headline)
                
                Spacer()
                
                if cloudKitService.isCheckingStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        cloudKitService.checkAccountStatus()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote)
                    }
                }
            }
            
            if let errorMessage = cloudKitService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .onAppear {
            if cloudKitService.cloudKitStatus == .unknown {
                cloudKitService.checkAccountStatus()
            }
        }
    }
    
    private var statusIcon: String {
        switch cloudKitService.cloudKitStatus {
        case .available:
            return "checkmark.circle.fill"
        case .restricted, .noAccount:
            return "exclamationmark.circle.fill"
        case .temporarilyUnavailable:
            return "clock.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch cloudKitService.cloudKitStatus {
        case .available:
            return .green
        case .restricted, .noAccount:
            return .orange
        case .temporarilyUnavailable:
            return .yellow
        case .unknown:
            return .gray
        }
    }
    
    private var statusText: String {
        switch cloudKitService.cloudKitStatus {
        case .available:
            return "iCloud同步已启用"
        case .restricted:
            return "iCloud访问受限"
        case .noAccount:
            return "未登录iCloud账户"
        case .temporarilyUnavailable:
            return "iCloud暂时不可用"
        case .unknown:
            return "iCloud状态未知"
        }
    }
} 
