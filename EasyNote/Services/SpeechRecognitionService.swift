//
//  SpeechRecognitionService.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import Foundation
import Speech
import AVFoundation
import Combine

enum RecordingState {
    case idle
    case recording
    case processing
    case finished
    case error(Error)

    var allowsTranscriptionActions: Bool {
        switch self {
        case .recording, .processing:
            return false
        case .idle, .finished, .error:
            return true
        }
    }
}

enum SpeechPermissionStatus: Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined

    init(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .restricted
        }
    }

    var isAvailable: Bool {
        self == .authorized
    }

    var failureMessage: String? {
        switch self {
        case .authorized:
            return nil
        case .denied:
            return "语音识别权限已关闭，请在系统设置中允许语音识别"
        case .restricted:
            return "当前设备限制了语音识别功能"
        case .notDetermined:
            return "语音识别权限尚未授权"
        }
    }
}

enum MicrophonePermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined

    init(_ permission: AVAudioSession.RecordPermission) {
        switch permission {
        case .granted:
            self = .granted
        case .denied:
            self = .denied
        case .undetermined:
            self = .notDetermined
        @unknown default:
            self = .denied
        }
    }

    var isAvailable: Bool {
        self == .granted
    }

    var failureMessage: String? {
        switch self {
        case .granted:
            return nil
        case .denied:
            return "麦克风权限已关闭，请在系统设置中允许麦克风访问"
        case .notDetermined:
            return "麦克风权限尚未授权"
        }
    }
}

class SpeechRecognitionService: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var recordingAudioFile: AVAudioFile?
    private var recordingURL: URL?
    private var isInputTapInstalled = false
    
    @Published var recordingState: RecordingState = .idle {
        didSet {
            NotificationCenter.default.post(name: Notification.Name("SpeechRecordingStateChanged"), object: recordingState)
        }
    }
    @Published var transcribedText: String = "" {
        didSet {
            NotificationCenter.default.post(name: Notification.Name("SpeechTranscriptionChanged"), object: transcribedText)
        }
    }
    @Published var isRecording: Bool = false {
        didSet {
            NotificationCenter.default.post(name: Notification.Name("SpeechRecordingStatusChanged"), object: isRecording)
        }
    }
    @Published var speechPermissionStatus: SpeechPermissionStatus = .notDetermined
    @Published var microphonePermissionStatus: MicrophonePermissionStatus = .notDetermined
    
    override init() {
        super.init()
        requestPermissions()
    }
    
    func refreshPermissionStatus() {
        speechPermissionStatus = SpeechPermissionStatus(SFSpeechRecognizer.authorizationStatus())
        microphonePermissionStatus = MicrophonePermissionStatus(AVAudioSession.sharedInstance().recordPermission)
    }

    func requestPermissions(completion: ((Bool) -> Void)? = nil) {
        refreshPermissionStatus()

        let group = DispatchGroup()
        var latestSpeechStatus = speechPermissionStatus
        var latestMicrophoneStatus = microphonePermissionStatus

        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                latestSpeechStatus = SpeechPermissionStatus(status)
                self.speechPermissionStatus = latestSpeechStatus
                switch status {
                case .authorized:
                    print("语音识别权限已授权")
                default:
                    print("语音识别权限未授权")
                }
                group.leave()
            }
        }
        
        // 请求麦克风权限 - 使用新的 API
        group.enter()
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    latestMicrophoneStatus = granted ? .granted : .denied
                    self.microphonePermissionStatus = latestMicrophoneStatus
                    if granted {
                        print("录音权限已授权")
                    } else {
                        print("录音权限未授权")
                    }
                    group.leave()
                }
            }
        } else {
            // 旧版本 iOS 继续使用旧 API
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    latestMicrophoneStatus = granted ? .granted : .denied
                    self.microphonePermissionStatus = latestMicrophoneStatus
                    if granted {
                        print("录音权限已授权")
                    } else {
                        print("录音权限未授权")
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion?(latestSpeechStatus.isAvailable && latestMicrophoneStatus.isAvailable)
        }
    }
    
    func startRecording() throws {
        // 重置状态
        transcribedText = ""
        tearDownRecordingPipeline(cancelRecognition: true)
        discardRecordingFile()
        refreshPermissionStatus()

        if case .denied = speechPermissionStatus, let message = speechPermissionStatus.failureMessage {
            let error = permissionError(message: message, code: 10)
            recordingState = .error(error)
            throw error
        }

        if case .restricted = speechPermissionStatus, let message = speechPermissionStatus.failureMessage {
            let error = permissionError(message: message, code: 10)
            recordingState = .error(error)
            throw error
        }

        if case .denied = microphonePermissionStatus, let message = microphonePermissionStatus.failureMessage {
            let error = permissionError(message: message, code: 11)
            recordingState = .error(error)
            throw error
        }
        
        // 检查语音识别器是否可用
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            let error = NSError(domain: "SpeechRecognitionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "语音识别器不可用"])
            recordingState = .error(error)
            throw error
        }
        
        // 配置音频会话
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // 配置音频引擎和输入节点
        let inputNode = audioEngine.inputNode
        
        guard let recognitionRequest = recognitionRequest else {
            let error = NSError(domain: "SpeechRecognitionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建语音识别请求"])
            recordingState = .error(error)
            throw error
        }
        
        // 设置请求属性
        recognitionRequest.shouldReportPartialResults = true
        
        // 开始识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                self.transcribedText = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                self.tearDownRecordingPipeline(cancelRecognition: false)
                self.recordingState = .finished
                self.isRecording = false
            }
        }
        
        // 配置音频格式
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // 创建本地音频文件，和语音识别共用同一个输入 tap。
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingFileURL = documentsDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).caf")
        do {
            recordingAudioFile = try AVAudioFile(forWriting: recordingFileURL, settings: recordingFormat.settings)
            recordingURL = recordingFileURL
        } catch {
            tearDownRecordingPipeline(cancelRecognition: true)
            recordingState = .error(error)
            throw error
        }
        
        // 安装音频输入节点的tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)

            do {
                try self.recordingAudioFile?.write(from: buffer)
            } catch {
                DispatchQueue.main.async {
                    self.discardRecordingFile()
                    self.tearDownRecordingPipeline(cancelRecognition: true)
                    self.recordingState = .error(error)
                    self.isRecording = false
                }
            }
        }
        isInputTapInstalled = true
        
        // 启动音频引擎
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            tearDownRecordingPipeline(cancelRecognition: true)
            discardRecordingFile()
            recordingState = .error(error)
            isRecording = false
            throw error
        }

        recordingState = .recording
        isRecording = true
    }
    
    func stopRecording() throws {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        recordingAudioFile = nil
        recordingState = .processing
        isRecording = false
    }
    
    func saveRecordingWithTranscription() -> (audioURL: URL?, transcription: String) {
        // 验证音频文件是否存在
        var validURL: URL? = recordingURL
        if let url = recordingURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                print("警告: 录音文件不存在: \(url.path)")
                validURL = nil
            }
        }
        
        recordingURL = nil
        return (validURL, transcribedText)
    }

    private func permissionError(message: String, code: Int) -> NSError {
        NSError(
            domain: "SpeechRecognitionService",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func tearDownRecordingPipeline(cancelRecognition: Bool) {
        audioEngine.stop()

        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }

        if cancelRecognition {
            recognitionTask?.cancel()
        }

        recognitionRequest = nil
        recognitionTask = nil
        recordingAudioFile = nil
    }

    private func discardRecordingFile() {
        guard let recordingURL else {
            return
        }

        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
    }
}
