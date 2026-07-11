# KeyboardObserver.swift

## Responsibility

- Publish keyboard visibility and height from UIKit keyboard notifications.
- Own exact Combine cancellation tokens for the views that subscribe.

## Boundaries

- Do not own text focus, editor content, layout policy, or persistence behavior.

## Behavior Notes

- `start()` is idempotent and registers one show plus one hide subscription.
- `stop()` cancels both subscriptions and resets keyboard state.

## Tests

- Verify repeated `start()` calls do not increase registration count and `stop()` removes all registrations.
