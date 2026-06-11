# Diary Search And Filter

## Summary

Make the diary list a stable search and filter entry point without mutating the source diary collection. This slice adds a pure query model, richer filters, and focused tests while keeping the SwiftData schema unchanged.

## Scope

- Add a pure `DiaryEntryQuery` helper for search, tag, mood, favorite, date range, and sort behavior.
- Update `DiaryViewModel` so `diaryEntries` remains the full fetched source list and `entries` is derived from the active query.
- Update `DiaryListView` to support stacked filters and clear-all behavior without refetching just to undo filtering.
- Do not change `DiaryEntry` persisted fields or CloudKit behavior.

## Implementation

- Store the active query in `DiaryViewModel` and expose `entries` as query-applied results over `diaryEntries`.
- Replace search/tag/sort methods that overwrite `diaryEntries` with query updates.
- Add mood, favorite-only, and inclusive date-range controls to the existing filter sheet.
- Keep list grouping based on the filtered result while tag/mood filter options come from the full source list.

## Test Plan

- Add tests for title/content/tag search.
- Add tests for tag, mood, favorite, and date-range filters.
- Add tests for combined search plus filters.
- Add tests for all sort options and empty-query behavior.
- Run `git diff --check`, Markdown link checks, and `xcodebuild -list -project EasyNote.xcodeproj`.
- Rely on GitHub CI for simulator unit tests if the local runtime remains unavailable.

## Assumptions

- Date range filtering is inclusive by day in the UI.
- Empty search text and unset filters return the full source list.
- Title sorting is localized case-insensitive with creation date as a deterministic tie-breaker.
