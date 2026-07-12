# AIContentConsentStore.swift

## Responsibility

- Define and persist the app-wide DeepSeek content-sharing consent decision.
- Provide stable disclosure and blocked-request messages used by Settings and the network boundary.

## Boundaries

- Do not read, write, migrate, or infer API credentials.
- Do not grant consent from credential presence, migration, or successful network behavior.

## Behavior Notes

- `ai_content_consent_granted` defaults to denied when absent.
- Grant and revoke are explicit, and revocation blocks future provider requests without deleting the Keychain item.
- The disclosure distinguishes selected text prompt content from audio files and Authorization-header credential use.

## Tests

- `AIPrivacyTests` verifies default denial plus grant and revoke transitions.
- HTTP-boundary tests verify denied consent never reaches the client adapter.
