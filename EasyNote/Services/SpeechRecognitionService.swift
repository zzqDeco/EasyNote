//
//  SpeechRecognitionService.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation
import Combine
import OSLog

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

    var afterRecognitionCompletion: RecordingState {
        switch self {
        case .error:
            return self
        case .idle, .recording, .processing, .finished:
            return .finished
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

    @available(iOS 17.0, *)
    static var current: MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .denied
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

final class SpeechRecognitionSessionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeSessionID: UUID?

    func activate(_ sessionID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard activeSessionID == nil else {
            return false
        }
        activeSessionID = sessionID
        return true
    }

    func isActive(_ sessionID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeSessionID == sessionID
    }

    @discardableResult
    func invalidate(_ sessionID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard activeSessionID == sessionID else {
            return false
        }
        activeSessionID = nil
        return true
    }
}

@MainActor
private final class SpeechPermissionCompletion {
    private let action: ((Bool) -> Void)?

    init(_ action: ((Bool) -> Void)?) {
        self.action = action
    }

    func callAsFunction(_ isGranted: Bool) {
        action?(isGranted)
    }
}

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "EasyNote", category: "SpeechRecognition")
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let sessionGate = SpeechRecognitionSessionGate()
    
    private var recordingAudioFile: AVAudioFile?
    private var recordingURL: URL?
    private var isInputTapInstalled = false
    private var activeRecognitionSessionID: UUID?
    
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
        microphonePermissionStatus = .current
    }

    func requestPermissions(completion: ((Bool) -> Void)? = nil) {
        refreshPermissionStatus()
        let completion = SpeechPermissionCompletion(completion)

        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speechPermissionStatus = SpeechPermissionStatus(status)
                switch status {
                case .authorized:
                    Self.logger.info("Speech recognition permission authorized")
                default:
                    Self.logger.notice("Speech recognition permission unavailable")
                }

                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        self.microphonePermissionStatus = granted ? .granted : .denied
                        if granted {
                            Self.logger.info("Microphone permission authorized")
                        } else {
                            Self.logger.notice("Microphone permission unavailable")
                        }
                        completion(
                            self.speechPermissionStatus.isAvailable
                                && self.microphonePermissionStatus.isAvailable
                        )
                    }
                }
            }
        }
    }
    
    func startRecording() throws {
        guard activeRecognitionSessionID == nil else {
            Self.logger.notice("Rejected overlapping speech recording start")
            throw NSError(
                domain: "SpeechRecognitionService",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "已有录音正在进行，请先停止当前录音"]
            )
        }

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
        let recognitionSessionID = UUID()
        guard sessionGate.activate(recognitionSessionID) else {
            Self.logger.notice("Speech session gate rejected a recording start")
            throw NSError(
                domain: "SpeechRecognitionService",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "已有录音正在进行，请先停止当前录音"]
            )
        }
        activeRecognitionSessionID = recognitionSessionID
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
            let transcription = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let didFail = error != nil

            DispatchQueue.main.async {
                self?.handleRecognitionCallback(
                    sessionID: recognitionSessionID,
                    transcription: transcription,
                    isFinal: isFinal,
                    didFail: didFail
                )
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

        guard let recordingAudioFile else {
            let error = NSError(domain: "SpeechRecognitionService", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法创建本地录音文件"])
            tearDownRecordingPipeline(cancelRecognition: true)
            recordingState = .error(error)
            throw error
        }
        
        // 安装音频输入节点的tap
        let sessionGate = sessionGate
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard sessionGate.isActive(recognitionSessionID) else {
                return
            }
            recognitionRequest.append(buffer)

            do {
                try recordingAudioFile.write(from: buffer)
            } catch {
                DispatchQueue.main.async {
                    self?.handleAudioWriteFailure(error, sessionID: recognitionSessionID)
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
        guard let activeRecognitionSessionID,
              sessionGate.isActive(activeRecognitionSessionID) else {
            throw NSError(
                domain: "SpeechRecognitionService",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "当前没有正在进行的录音"]
            )
        }

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

    func cancelRecording() {
        tearDownRecordingPipeline(cancelRecognition: true)
        discardRecordingFile()
        transcribedText = ""
        recordingState = .idle
        isRecording = false
    }
    
    func saveRecordingWithTranscription() -> (audioURL: URL?, transcription: String) {
        // 验证音频文件是否存在
        var validURL: URL? = recordingURL
        if let url = recordingURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                Self.logger.error("Recorded audio file is unavailable")
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
        if let activeRecognitionSessionID {
            sessionGate.invalidate(activeRecognitionSessionID)
            self.activeRecognitionSessionID = nil
        }

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

    private func handleRecognitionCallback(
        sessionID: UUID,
        transcription: String?,
        isFinal: Bool,
        didFail: Bool
    ) {
        guard activeRecognitionSessionID == sessionID,
              sessionGate.isActive(sessionID) else {
            Self.logger.debug("Ignored callback from an inactive speech session")
            return
        }

        if let transcription {
            transcribedText = transcription
        }

        if didFail || isFinal {
            tearDownRecordingPipeline(cancelRecognition: false)
            recordingState = recordingState.afterRecognitionCompletion
            isRecording = false
        }
    }

    private func handleAudioWriteFailure(_ error: Error, sessionID: UUID) {
        guard activeRecognitionSessionID == sessionID,
              sessionGate.isActive(sessionID) else {
            return
        }

        tearDownRecordingPipeline(cancelRecognition: true)
        discardRecordingFile()
        recordingState = .error(error)
        isRecording = false
        Self.logger.error("Audio buffer write failed; recording session invalidated")
    }

    private func discardRecordingFile() {
        guard let recordingURL else {
            return
        }

        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
    }
}

extension SpeechRecognitionService: @preconcurrency SpeechRecognitionProviding {
    var transcribedTextPublisher: AnyPublisher<String, Never> {
        $transcribedText.eraseToAnyPublisher()
    }

    var recordingStatePublisher: AnyPublisher<RecordingState, Never> {
        $recordingState.eraseToAnyPublisher()
    }

    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }

    var speechPermissionStatusPublisher: AnyPublisher<SpeechPermissionStatus, Never> {
        $speechPermissionStatus.eraseToAnyPublisher()
    }

    var microphonePermissionStatusPublisher: AnyPublisher<MicrophonePermissionStatus, Never> {
        $microphonePermissionStatus.eraseToAnyPublisher()
    }
}
