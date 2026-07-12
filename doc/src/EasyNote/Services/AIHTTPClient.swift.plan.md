# AIHTTPClient.swift

## Responsibility

- Provide the injectable publisher-based HTTP transport used by `OpenAIService`.
- Adapt production `URLSession` behavior without owning prompts, credentials, consent, or response parsing.

## Boundaries

- Do not decide whether a request is privacy-eligible.
- Do not persist, inspect, or log request content or Authorization headers.

## Behavior Notes

- `OpenAIService` must complete credential and consent guards before calling this boundary.
- The production adapter preserves `URLSession` data/response output and `URLError` failure semantics.

## Tests

- `AIPrivacyTests` injects a recording client and asserts zero calls for denied consent and empty credentials.
