# AIPrivacyTests.swift

## Responsibility

- Verify AI credential storage, migration safety, consent lifecycle, and pre-network privacy guards.

## Boundaries

- Use in-memory Security, credential, consent, and HTTP fakes; do not depend on a real Keychain item or live DeepSeek endpoint.
- Never use credential-shaped production secrets in fixtures.

## Behavior Notes

- CRUD coverage inspects the production service, account, and accessibility attributes.
- Migration coverage proves success is idempotent and failures retain the legacy defaults value.
- Request coverage proves the HTTP adapter is untouched when consent or credentials are missing.

## Tests

- Compile through generic simulator `build-for-testing` and run on a concrete simulator when the local runtime is available.
