//
//  OpenAIService.swift
//  EasyNote
//
//  Created by 赵子谦 on 2025/3/1.
//

import Foundation
import Combine

enum OpenAIError: Error {
    case invalidURL
    case invalidResponse
    case requestFailed(Error)
    case decodingFailed(Error)
    case apiError(String)
}

class OpenAIService: ObservableObject {
    // 使用计算属性从UserDefaults读取API密钥
    var apiKey: String {
        get {
            return UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "openai_api_key")
        }
    }
    
    // DeepSeek API 端点
    private let baseURL = "https://api.deepseek.com/v1/chat/completions"
    
    @Published var isProcessing = false
    
    // 存储Combine订阅的集合
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 初始化时不需要传入API密钥，而是从UserDefaults读取
    }
    
    func generateSummary(from text: String) -> AnyPublisher<String, OpenAIError> {
        let prompt = """
        系统：请根据以下日记内容，生成一个简洁而有深度的总结。
        
        总结要点：
        1. 提炼出日记中的关键事件、活动和经历
        2. 捕捉作者的核心情绪状态和心理变化
        3. 概括重要的思考、决定和领悟
        4. 注意日期相关的上下文（如季节特点、节日、周期性活动等）
        5. 识别出日记中提到的人际关系和互动
        
        请以第三人称视角撰写总结，风格简洁专业。总结应当在80-120字之间，突出显示关键点和情感变化，但不要添加原文中没有的内容或主观解读。
        
        日记内容：
        \(text)
        """
        
        return sendRequest(prompt: prompt)
    }
    
    func refineTranscription(text: String) -> AnyPublisher<String, OpenAIError> {
        let prompt = """
        系统：你是一位专业的日记内容润色助手。你的任务是优化语音识别文本，使其更加流畅、连贯，并修正语法或表达错误。
        
        润色指南：
        1. 保持原文的核心意思、情感和个人风格
        2. 修正语法错误、口语化表达和重复内容
        3. 优化段落结构，使内容更有逻辑性
        4. 增强时间和日期相关的表达，使日期、时间点和事件顺序更加清晰
        5. 明确日记中提到的人物、地点和事件
        6. 保留作者的个人感受和情绪表达，增强情感深度
        
        直接输出优化后的文本，不要添加任何解释、标签、引号或前缀。确保优化后的文本保持日记的自然风格，就像是用户自己写的一样。
        
        用户文本：
        \(text)
        """
        
        return sendRequest(prompt: prompt)
    }
    
    func analyzeDiaryContent(text: String) -> AnyPublisher<(moods: [String], tags: [String]), OpenAIError> {
        let prompt = """
        系统：你是一位专业的日记内容分析助手。基于用户的日记内容及其写作日期，请深入分析并提供以下两项内容：
        
        1. 推荐3个最能准确反映用户情感状态的心情标签：
           - 请考虑日记中的用词、语气和表达方式
           - 注意区分显性表达的情绪和潜在的情感状态
           - 如果日记内容跨越多天，请重点关注最近的情绪变化
        
        2. 推荐3-5个最适合的主题标签：
           - 标签应精确反映日记的核心主题、活动或关键内容
           - 考虑日期相关的季节性、节日或特殊事件因素
           - 识别用户可能的习惯、兴趣和关注点
           - 如果内容提及计划或目标，添加相关的标签
        
        请以JSON格式返回结果，格式如下：
        {
          "moods": ["心情1", "心情2", "心情3"],
          "tags": ["标签1", "标签2", "标签3", "标签4", "标签5"]
        }
        
        心情选项包括但不限于：开心、平静、疲惫、焦虑、兴奋、伤心、愤怒、满足、困惑、感激、期待、担忧、自信、失落、怀旧、憧憬、沮丧、释然。
        
        用户日记内容：
        \(text)
        """
        
        return sendRequest(prompt: prompt)
            .mapError { $0 } // 保持OpenAIError类型
            .tryMap { responseStr -> (moods: [String], tags: [String]) in
                // 尝试解析JSON响应
                guard let data = responseStr.data(using: .utf8) else {
                    throw OpenAIError.decodingFailed(NSError(domain: "OpenAIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法将响应转换为数据"]))
                }
                
                struct AnalysisResponse: Decodable {
                    let moods: [String]
                    let tags: [String]
                }
                
                do {
                    let response = try JSONDecoder().decode(AnalysisResponse.self, from: data)
                    return (moods: response.moods, tags: response.tags)
                } catch {
                    // 如果解析失败，返回默认值
                    print("解析AI分析结果失败: \(error.localizedDescription)")
                    return (moods: ["平静", "思考", "感动"], tags: ["日常", "生活", "随想"])
                }
            }
            .mapError { error -> OpenAIError in
                // 确保所有错误都是OpenAIError类型
                if let openAIError = error as? OpenAIError {
                    return openAIError
                } else {
                    return OpenAIError.decodingFailed(error)
                }
            }
            .eraseToAnyPublisher()
    }
    
    // 扩展文本内容
    func expandText(text: String) -> AnyPublisher<String, OpenAIError> {
        let prompt = """
        系统：你是一位专业的文本扩展助手。请基于用户提供的文本，扩展并丰富内容，使其更加详细、生动和有深度。保持原文的风格和核心意思，但添加更多细节、描述和上下文。直接返回扩展后的完整文本，不要添加任何解释、引号或前缀。

        用户文本：
        \(text)
        """
        
        return sendRequest(prompt: prompt)
    }
    
    // 总结文本内容
    func summarizeText(text: String) -> AnyPublisher<String, OpenAIError> {
        let prompt = """
        系统：你是一位专业的文本总结助手。请将用户提供的文本进行简洁明了的总结，保留核心要点和关键信息，同时保持原文的语气和风格。总结应当清晰、准确且易于理解。直接返回总结后的文本，不要添加任何解释、引号或前缀。

        用户文本：
        \(text)
        """
        
        return sendRequest(prompt: prompt)
    }
    
    // 聊天功能
    func chat(prompt: String) async throws -> String {
        // 创建一个返回异步结果的方法
        return try await withCheckedThrowingContinuation { continuation in
            sendRequest(prompt: prompt)
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            break
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        continuation.resume(returning: response)
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // 根据用户最近的日记生成推荐的活动和待办事项
    func generateRecommendations(from diaryContent: String) -> AnyPublisher<(recommendations: [String], todos: [String]), OpenAIError> {
        let prompt = """
        系统：你是一位智能个人助手。用户将提供最近的日记内容以及当前日期。请根据用户的日记内容、心情变化、日期信息和季节特点，为用户的今天生成两项内容：
        
        1. 5-6个个性化推荐活动：
           - 这些活动应基于用户在日记中表达的兴趣、习惯和情感状态
           - 考虑用户日记中提到的计划和未完成事项
           - 考虑当前日期与用户日记日期之间的关系（如计划的后续行动）
           - 根据当前季节和可能的天气条件提供适合的室内或室外活动
           - 如果用户日记中有持续的主题或目标，提供相关的活动建议
        
        2. 3-5个具体待办事项：
           - 这些应该基于用户在日记中提到的任务、目标或需要跟进的事项
           - 优先考虑用户明确提到但尚未完成的任务
           - 为用户提出的长期目标分解出可执行的小步骤
           - 根据日期的连续性，提醒用户可能需要继续的项目或任务
           - 如果用户日记中提到的某些困难，提供解决方案相关的待办事项
        
        请以JSON格式返回结果，格式如下：
        {
          "recommendations": ["建议活动1", "建议活动2", "建议活动3", "建议活动4", "建议活动5"],
          "todos": ["待办事项1", "待办事项2", "待办事项3", "待办事项4"]
        }
        
        确保推荐是具体、可操作、个性化的，并且与用户的日记内容和当前日期紧密相关。推荐和待办事项应该简洁明了，直接可行，不要过于宽泛。如果日记中没有足够的信息，可以基于当前日期和季节生成一些通用的、积极的建议。
        
        \(diaryContent)
        """
        
        return sendRequest(prompt: prompt)
            .mapError { $0 }
            .tryMap { responseStr -> (recommendations: [String], todos: [String]) in
                // 尝试解析JSON响应
                guard let data = responseStr.data(using: .utf8) else {
                    throw OpenAIError.decodingFailed(NSError(domain: "OpenAIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法将响应转换为数据"]))
                }
                
                struct RecommendationsResponse: Decodable {
                    let recommendations: [String]
                    let todos: [String]
                }
                
                do {
                    let response = try JSONDecoder().decode(RecommendationsResponse.self, from: data)
                    return (recommendations: response.recommendations, todos: response.todos)
                } catch {
                    // 如果解析失败，返回默认值
                    print("解析AI推荐结果失败: \(error.localizedDescription)")
                    print("原始响应: \(responseStr)")
                    
                    // 尝试使用正则表达式提取内容
                    let recommendations = self.extractRecommendationsFromText(responseStr)
                    let todos = self.extractTodosFromText(responseStr)
                    
                    if !recommendations.isEmpty || !todos.isEmpty {
                        return (recommendations: recommendations, todos: todos)
                    }
                    
                    // 如果所有尝试都失败，返回默认推荐
                    return (
                        recommendations: ["花点时间阅读一本书", "尝试冥想15分钟", "进行30分钟的有氧运动", "和朋友或家人联系", "学习一项新技能"],
                        todos: ["记录今天的心情和想法", "整理工作计划", "确保充足的水分摄入"]
                    )
                }
            }
            .mapError { error -> OpenAIError in
                if let openAIError = error as? OpenAIError {
                    return openAIError
                } else {
                    return OpenAIError.decodingFailed(error)
                }
            }
            .eraseToAnyPublisher()
    }
    
    // 从文本中提取推荐活动
    private func extractRecommendationsFromText(_ text: String) -> [String] {
        var recommendations: [String] = []
        
        // 尝试不同的模式来匹配推荐
        let patterns = [
            "\"recommendations\"\\s*:\\s*\\[([^\\]]+)\\]",  // 标准JSON格式
            "recommendations\\s*:?\\s*\\[([^\\]]+)\\]",     // 宽松的JSON格式
            "推荐活动：\\s*([\\s\\S]*?)(?=待办事项|$)",       // 中文标记
            "推荐：\\s*([\\s\\S]*?)(?=待办|$)"              // 简化中文标记
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                    let matchedText = String(text[range])
                    
                    // 分割项目
                    let items = matchedText.components(separatedBy: CharacterSet(charactersIn: ",\""))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0 != "," && $0 != "\"" }
                    
                    if !items.isEmpty {
                        recommendations.append(contentsOf: items)
                        break
                    }
                }
            }
        }
        
        // 如果没有找到匹配，尝试查找带编号的列表
        if recommendations.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            var collectingRecommendations = false
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmedLine.lowercased().contains("推荐") || trimmedLine.lowercased().contains("建议") {
                    collectingRecommendations = true
                    continue
                }
                
                if collectingRecommendations {
                    if trimmedLine.lowercased().contains("待办") || trimmedLine.isEmpty {
                        collectingRecommendations = false
                        continue
                    }
                    
                    // 移除可能的编号或符号
                    let cleanLine = trimmedLine.replacingOccurrences(of: "^[0-9-\\.•\\*\\+]+\\s*", with: "", options: .regularExpression)
                    if !cleanLine.isEmpty {
                        recommendations.append(cleanLine)
                    }
                }
            }
        }
        
        return recommendations
    }
    
    // 从文本中提取待办事项
    private func extractTodosFromText(_ text: String) -> [String] {
        var todos: [String] = []
        
        // 尝试不同的模式来匹配待办事项
        let patterns = [
            "\"todos\"\\s*:\\s*\\[([^\\]]+)\\]",       // 标准JSON格式
            "todos\\s*:?\\s*\\[([^\\]]+)\\]",          // 宽松的JSON格式
            "待办事项：\\s*([\\s\\S]*?)(?=推荐|$)",       // 中文标记
            "待办：\\s*([\\s\\S]*?)(?=推荐|$)"          // 简化中文标记
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                    let matchedText = String(text[range])
                    
                    // 分割项目
                    let items = matchedText.components(separatedBy: CharacterSet(charactersIn: ",\""))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0 != "," && $0 != "\"" }
                    
                    if !items.isEmpty {
                        todos.append(contentsOf: items)
                        break
                    }
                }
            }
        }
        
        // 如果没有找到匹配，尝试查找带编号的列表
        if todos.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            var collectingTodos = false
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmedLine.lowercased().contains("待办") || trimmedLine.lowercased().contains("任务") {
                    collectingTodos = true
                    continue
                }
                
                if collectingTodos {
                    if trimmedLine.lowercased().contains("推荐") || trimmedLine.isEmpty {
                        collectingTodos = false
                        continue
                    }
                    
                    // 移除可能的编号或符号
                    let cleanLine = trimmedLine.replacingOccurrences(of: "^[0-9-\\.•\\*\\+]+\\s*", with: "", options: .regularExpression)
                    if !cleanLine.isEmpty {
                        todos.append(cleanLine)
                    }
                }
            }
        }
        
        return todos
    }
    
    private func sendRequest(prompt: String) -> AnyPublisher<String, OpenAIError> {
        let currentAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentAPIKey.isEmpty else {
            return Fail(error: OpenAIError.apiError("请在设置中添加DeepSeek API密钥后再使用AI功能"))
                .eraseToAnyPublisher()
        }
        
        guard let url = URL(string: baseURL) else {
            return Fail(error: OpenAIError.invalidURL).eraseToAnyPublisher()
        }
        
        // 构建请求体 - 使用DeepSeek推荐的模型
        let requestBody: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(currentAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // 设置较短的超时时间，避免用户长时间等待
        request.timeoutInterval = 15
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return Fail(error: OpenAIError.requestFailed(error)).eraseToAnyPublisher()
        }
        
        // 确保在主线程上更新UI状态
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        // 发送请求
        return URLSession.shared.dataTaskPublisher(for: request)
            .mapError { error -> OpenAIError in
                // 提供更明确的错误信息
                let urlError = error
                switch urlError.code {
                case .timedOut:
                    return OpenAIError.apiError("请求超时，服务器响应时间过长")
                case .notConnectedToInternet:
                    return OpenAIError.apiError("网络连接已断开，请检查您的网络设置")
                case .cannotConnectToHost:
                    return OpenAIError.apiError("无法连接到服务器，服务可能暂时不可用")
                default:
                    return OpenAIError.requestFailed(error)
                }
            }
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAIError.invalidResponse
                }
                
                // 提供更详细的错误处理
                if httpResponse.statusCode != 200 {
                    // 根据状态码提供更具体的错误信息
                    switch httpResponse.statusCode {
                    case 401:
                        throw OpenAIError.apiError("API密钥无效或已过期")
                    case 429:
                        throw OpenAIError.apiError("超出API请求限制，请稍后再试")
                    case 500...599:
                        throw OpenAIError.apiError("服务器错误，请稍后再试")
                    default:
                        throw OpenAIError.apiError("API返回错误 (状态码: \(httpResponse.statusCode))")
                    }
                }
                
                return data
            }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .mapError { error in
                if let openAIError = error as? OpenAIError {
                    return openAIError
                } else {
                    return OpenAIError.decodingFailed(error)
                }
            }
            .map { response in
                if let content = response.choices.first?.message.content {
                    return content
                } else {
                    return "无法生成内容"
                }
            }
            .handleEvents(receiveCompletion: { [weak self] _ in
                // 确保在主线程上更新UI状态
                DispatchQueue.main.async {
                    self?.isProcessing = false
                }
            })
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// OpenAI API响应模型
struct OpenAIResponse: Decodable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    
    struct Choice: Decodable {
        let index: Int
        let message: Message
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct Message: Decodable {
        let role: String
        let content: String
    }
} 
