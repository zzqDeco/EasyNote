# OpenAIService.swift

## Responsibility

- Own the DeepSeek OpenAI-compatible chat-completions HTTP boundary.
- Build prompts for diary summary, transcription refinement, diary analysis, text expansion, summarization, chat, and recommendations.
- Normalize request failures into `OpenAIError`.

## Boundaries

- Do not store default API keys or committed provider credentials here.
- Do not let views build raw HTTP requests.
- Do not leak provider response shapes outside the service boundary.

## Behavior Notes

- API key is read from `UserDefaults.standard["openai_api_key"]`.
- Empty API key fails closed before sending a request.
- The current endpoint is `https://api.deepseek.com/v1/chat/completions`.
- Recommendation and analysis parsing currently expects JSON but has fallback parsing/defaults.

## Tests

- Secret scan should not find `sk-` style keys in the repository.
- Future changes should extract JSON parsing into testable helpers before broadening AI behavior.
