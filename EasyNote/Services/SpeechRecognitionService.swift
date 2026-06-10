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
}

class SpeechRecognitionService: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
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
    
    override init() {
        super.init()
        requestPermissions()
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("语音识别权限已授权")
                default:
                    print("语音识别权限未授权")
                }
            }
        }
        
        // 请求麦克风权限 - 使用新的 API
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("录音权限已授权")
                    } else {
                        print("录音权限未授权")
                    }
                }
            }
        } else {
            // 旧版本 iOS 继续使用旧 API
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("录音权限已授权")
                    } else {
                        print("录音权限未授权")
                    }
                }
            }
        }
    }
    
    func startRecording() throws {
        // 重置状态
        transcribedText = ""
        
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
        
        // 创建录音文件URL
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
        
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
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                self.recordingState = .finished
                self.isRecording = false
            }
        }
        
        // 配置音频格式
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 安装音频输入节点的tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // 启动音频引擎
        audioEngine.prepare()
        
        try audioEngine.start()
        recordingState = .recording
        isRecording = true
    }
    
    func stopRecording() throws {
        audioEngine.stop()
        recognitionRequest?.endAudio()
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
        
        return (validURL, transcribedText)
    }
} 