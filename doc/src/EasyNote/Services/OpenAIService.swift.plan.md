# OpenAIService.swift

## Responsibility

- Own the DeepSeek OpenAI-compatible chat-completions HTTP boundary.
- Build prompts for diary summary, transcription refinement, diary analysis, text expansion, summarization, chat, and recommendations.
- Normalize request failures into `OpenAIError`.
- Enforce Keychain credential and explicit content-consent checks before invoking HTTP transport.
- Bridge chat publishers through their async sequence so cancelling a session request cancels the underlying subscription and clears processing state.
- Delegate model-content parsing for diary analysis and recommendations to `AIResponseParser`.

## Boundaries

- Do not store default API keys or committed provider credentials here.
- Do not infer consent from an existing or migrated credential.
- Do not let views build raw HTTP requests.
- Do not leak provider response shapes outside the service boundary.
- Do not add parser-specific regex or fallback branching here; keep content parsing in `AIResponseParser`.
- Do not own AI result history or apply/discard behavior; that confirmation state belongs to ViewModels and views.

## Behavior Notes

- API key is read through `CredentialStoreProviding`; startup opportunistically runs the verified legacy migration.
- Empty credentials and denied consent fail closed before the injected HTTP client is called.
- The API key is used only in the Authorization header and is never added to prompt content.
- The current endpoint is `https://api.deepseek.com/v1/chat/completions`.
- Recommendation and analysis parsing supports JSON, fenced JSON, embedded JSON, and controlled fallbacks through `AIResponseParser`.

## Tests

- Secret scan should not find `sk-` style keys in the repository.
- Unit tests cover parser fallback behavior plus empty-key and denied-consent no-network paths.
