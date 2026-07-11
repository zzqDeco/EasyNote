# Persistence Feedback And Todo Drafts

## Summary

- Keep todo creation as an unpersisted draft until the user explicitly saves.
- Keep diary and todo create, edit, and detail-delete screens visible when SwiftData operations fail, with the persistence error shown for retry.
- Remove duplicate-prone keyboard observer registration and preserve legacy todo recurrence labels.

## Scope

- Add a pure `TodoDraft` used by Explore and unified todo creation.
- Add a pure persistence feedback decision used by UI actions to dismiss only after ViewModel success.
- Centralize recurrence parsing for current Chinese values and legacy English values.
- Replace invalid keyboard observer removal in `UnifiedAddView` and `CreateDiaryView` with one token-owning, idempotent observer.
- Add focused tests and synchronize acceptance, interface, model, view, and test source notes.
- Do not change the SwiftData schema, Settings, SwiftData bootstrap, reminder behavior, accessibility identifiers, or unrelated product flows.

## Implementation

- `TodoDraft` stores title, priority, optional deadline, notes, and recurrence selection without constructing or inserting a `TodoItem`.
- `TodoViewModel.addTodoItem(from:)` constructs and saves the model only from an explicit save action. Explore uses the same sheet for a new draft or an existing item, while Cancel only drops local draft state.
- `PersistenceFeedback` maps a ViewModel `Bool` result and error message to a dismissal decision and visible fallback error. Create, edit, and detail-delete views apply this decision without clearing input on failure.
- `TodoItem.RecurringInterval.parse(_:)` accepts canonical Chinese raw values and legacy English names. Display and recurrence planning reuse the parser.
- `KeyboardObserver` owns notification tokens, prevents repeated registration, unregisters exact tokens, and is shared by both affected views.

## Test Plan

- Verify creating and canceling an unsubmitted `TodoDraft` leaves SwiftData empty.
- Verify failed persistence feedback does not request dismissal and preserves the ViewModel error.
- Verify successful persistence feedback requests dismissal.
- Verify Chinese and legacy English recurrence values parse and display consistently.
- Verify repeated keyboard observer start calls do not duplicate registrations and stop removes them.
- Run `git diff --check`, Markdown relative-link validation, `xcodebuild -list`, focused generic-simulator build-for-testing, Release generic-device build, and focused tests when a compatible local simulator works.

## Assumptions

- Existing stored recurrence strings remain unchanged until a user edits a todo; compatibility is read-time and requires no migration.
- List-row deletes cannot retain a dismissed confirmation alert, so they keep the list visible and show a persistence error when deletion fails.
- Reminder side-effect failures remain separate from SwiftData save success and do not prevent dismissal after the model save succeeds.
