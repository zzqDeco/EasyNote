# AIResponseParser.swift

## Responsibility

- Own pure parsing and fallback behavior for AI-generated diary analysis and recommendation content.
- Normalize model text into app-level arrays without performing network requests or reading settings.

## Boundaries

- Do not build prompts, send HTTP requests, or read/write API keys here.
- Do not leak provider transport response shapes into callers; `OpenAIService` owns the chat-completions envelope.
- Do not add real provider calls to parser tests.

## Behavior Notes

- Diary analysis accepts JSON objects containing non-empty `moods` and `tags` arrays.
- Recommendations accept JSON objects containing non-empty `recommendations` and `todos` arrays.
- JSON may be the full response, inside a Markdown fenced block, or embedded in short surrounding prose.
- Recommendation parsing also accepts Chinese section/list fallback output for recommendation and todo sections.
- Completely malformed content returns stable default moods/tags or recommendations/todos.

## Tests

- `EasyNoteTests` covers valid JSON, fenced JSON, embedded JSON, Chinese list fallback, and malformed fallback behavior.
- Parser changes should update `doc/interfaces.plan.md` when accepted input/output contracts change.
