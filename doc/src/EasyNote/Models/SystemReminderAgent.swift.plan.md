# SystemReminderAgent.swift

## Responsibility

- Convert a `TodoItem` plus reminder mode and time context into a deterministic Apple Reminders proposal.
- Keep semantic lead-time decisions pure, repeatable, and unit-testable.
- Produce user-readable Chinese reasons for create/update or skip decisions.
- Map proposals to reconciliation operations that callers can execute consistently.

## Boundaries

- Do not import EventKit, SwiftData, UserNotifications, or network APIs.
- Do not mutate todos, write reminders, request permissions, or save app state.
- Do not call LLM providers; future LLM-assisted planning must remain behind `SystemReminderAgentProviding`.

## Behavior Notes

- The agent skips disabled mode, completed todos, missing deadlines, non-future deadlines, empty trimmed titles, and deadlines that are less than 60 seconds away.
- Meeting/call, travel, submission/deadline, preparation, and default tasks use fixed lead-time rules so tests can prove exact alarm dates.
- If the desired lead time is already in the past, the alarm clamps to `now + 60 seconds` when the deadline still leaves enough room.
- The marker format is `EasyNoteTodoID:<uuid>` and is used by `SystemReminderService` for idempotent EventKit writes.
- `SystemReminderProposalReconciler` maps active proposals to apply, completed skips to complete, ineligible skips to remove, and disabled-mode skips to ignore.

## Tests

- Unit tests cover every skip reason, every lead-time class, clamp behavior, marker generation, and proposal-to-operation mapping.
- ViewModel integration tests should use fake agents or fake writers only when they need to verify orchestration rather than lead-time rules.
