# Diary Review Insights

## Summary

- Add a local diary review surface that helps users understand writing cadence, tags, moods, and favorites without relying on AI.
- This slice belongs after backup because it improves everyday diary value while keeping data local and avoiding SwiftData schema changes.

## Scope

- Add a pure `DiaryReviewProjection` helper for monthly and fixed-window diary insights.
- Add a review entry in the diary screen for monthly overview, tag trends, mood distribution, and recent favorites.
- Update current-state docs and source notes for the new projection/UI boundary.
- Non-goals: persistent analytics tables, AI-generated insights, CloudKit sync, and schema changes.

## Implementation

- Derive all review data from the full diary list (`DiaryViewModel.allEntries`), not from the active search/filter result.
- Use `Calendar.current` by default, while tests pass an explicit calendar and reference date.
- Support fixed windows for recent 7 days, recent 30 days, and current month.
- Aggregate monthly entry counts, favorite counts, mood distribution, and top tags.
- Sort tag trends by count descending, then localized tag name ascending for stable ties.
- Keep the UI read-only. Editing, deleting, favorite toggles, and search/filter remain owned by existing diary list/detail flows.

## Test Plan

- Unit tests cover monthly counts, favorite counts, mood distribution, top tag ordering, empty input, and fixed date-window boundaries.
- Local checks: `git diff --check`, markdown relative link check, `xcodebuild -list -project EasyNote.xcodeproj`, and simulator `xcodebuild test` when a compatible runtime is installed.
- PR CI must pass `EasyNoteTests`.
- Manual smoke: enter diary review from the diary tab with multiple entries, verify non-empty charts/lists, verify empty state, and confirm active search/filter does not change review results.

## Assumptions

- Review insights are local, deterministic projections only.
- Existing diary `mood` values remain strings and are displayed with the same mood label helper used by diary rows.
- Persisted or AI-written long-form reflections can be handled in a future plan.
