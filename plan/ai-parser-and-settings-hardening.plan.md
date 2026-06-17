# AI Parser And Settings Hardening

## Summary

- Make AI response parsing testable and predictable without changing the DeepSeek request contract.
- Tighten Settings key-state feedback so empty keys clearly disable AI calls before any network request.

## Scope

- Add a pure `AIResponseParser` helper for diary analysis and recommendation responses.
- Refactor `OpenAIService` so it owns prompt construction, request execution, and error mapping, while parser fallback logic lives outside the HTTP client.
- Preserve the existing endpoint, model, temperature, max token limit, and `UserDefaults` key location.
- Update Settings to show whether a DeepSeek key is configured without displaying the key.
- Update AI boundary docs, source notes, README setup wording, and focused unit tests.

Non-goals:

- No real DeepSeek network tests.
- No new provider configuration or keychain migration.
- No changes to CloudKit, SwiftData schema, or chat/session storage.

## Implementation

- `AIResponseParser.parseDiaryAnalysis(_:)` accepts pure JSON, fenced JSON, or prose containing a JSON object and falls back to default moods/tags for malformed content.
- `AIResponseParser.parseRecommendations(_:)` accepts pure JSON, fenced JSON, prose containing a JSON object, and Chinese section/list output before falling back to default recommendations/todos.
- `OpenAIService` maps `sendRequest` output through the parser for analysis/recommendation APIs and keeps empty-key failures as `OpenAIError.apiError("请在设置中添加DeepSeek API密钥后再使用AI功能")`.
- `SettingsView` keeps `@AppStorage("openai_api_key")`, uses `SecureField`, and shows only configured/unconfigured state.

## Test Plan

- Unit tests cover diary analysis JSON, fenced JSON, and malformed fallback.
- Unit tests cover recommendations JSON, fenced JSON, Chinese list fallback, and malformed fallback.
- Unit test verifies empty API key fails before network with the existing user-visible error.
- Local checks: `git diff --check`, `xcodebuild -list -project EasyNote.xcodeproj`, docs link sanity, and secret scan.
- Full unit tests rely on GitHub CI if the local simulator runtime remains unavailable.

## Assumptions

- The DeepSeek response content remains `choices[0].message.content`; only content parsing is moved.
- Defaults remain the existing user-visible fallback values from `OpenAIService`.
- Storing the key in `UserDefaults` remains acceptable for this local-first MVP; keychain migration is deferred.
