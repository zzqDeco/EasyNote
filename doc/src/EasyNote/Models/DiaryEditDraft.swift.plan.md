# DiaryEditDraft.swift

## Responsibility

- Define the pure existing-diary edit transaction state.
- Centralize picker-index and stored-label mood compatibility through `MoodCatalog`.

## Boundaries

- Do not read or write SwiftData or recording files.
- Return superseded or discarded pending audio URLs to the owning flow for cleanup.

## Behavior Notes

- The draft snapshots original content, mood, tags, and audio URL while exposing mutable edit values.
- A pending recording overrides the original URL only for an explicit commit.
- Canonical mood storage uses Chinese labels; legacy numeric values are accepted as input but are never emitted as saved values.

## Tests

- Unit tests cover change detection, mood compatibility, pending recording replacement, and discard ownership.
