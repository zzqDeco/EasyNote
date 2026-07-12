import Foundation

enum ChatResponseOutcome: Equatable {
    case provider(message: String, relatedEntryIDs: [UUID])
    case local(LocalDiaryQueryResult)
    case failure(String)
    case cancelled
}

enum ChatResponseGenerator {
    static func generate(
        context: ChatRequestContext,
        provider: any ChatResponseProviding
    ) async -> ChatResponseOutcome {
        guard !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("AI 服务需要设置 API 密钥。请在设置中添加密钥后重试。")
        }

        do {
            let response = try await provider.chat(prompt: ChatPromptBuilder.makePrompt(from: context))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !response.isEmpty else {
                return localFallback(for: context)
            }
            return .provider(message: response, relatedEntryIDs: context.relatedEntryIDs)
        } catch is CancellationError {
            return .cancelled
        } catch OpenAIError.consentRequired {
            return .failure(AIContentConsentPolicy.requiredMessage)
        } catch {
            return localFallback(for: context)
        }
    }

    private static func localFallback(for context: ChatRequestContext) -> ChatResponseOutcome {
        guard let result = LocalDiaryQueryAnalyzer.analyze(
            query: context.userQuery,
            entries: context.diaryEntries
        ) else {
            return .failure("AI 服务暂时不可用，且没有找到可用于本地回答的匹配日记。请稍后重试。")
        }
        return .local(result)
    }
}
