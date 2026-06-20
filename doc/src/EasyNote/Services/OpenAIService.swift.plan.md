# OpenAIService.swift

## Responsibility

- Own the DeepSeek OpenAI-compatible chat-completions HTTP boundary.
- Build prompts for diary summary, transcription refinement, diary analysis, text expansion, summarization, chat, and recommendations.
- Normalize request failures into `OpenAIError`.
- Delegate model-content parsing for diary analysis and recommendations to `AIResponseParser`.

## Boundaries

- Do not store default API keys or committed provider credentials here.
- Do not let views build raw HTTP requests.
- Do not leak provider response shapes outside the service boundary.
- Do not add parser-specific regex or fallback branching here; keep content parsing in `AIResponseParser`.
- Do not own AI result history or apply/discard behavior; that confirmation state belongs to ViewModels and views.

## Behavior Notes

- API key is read from `UserDefaults.standard["openai_api_key"]`.
- Empty API key fails closed before sending a request.
- The current endpoint is `https://api.deepseek.com/v1/chat/completions`.
- Recommendation and analysis parsing supports JSON, fenced JSON, embedded JSON, and controlled fallbacks through `AIResponseParser`.

## Tests

- Secret scan should not find `sk-` style keys in the repository.
- Unit tests cover parser fallback behavior and the empty-key fail-closed path.
