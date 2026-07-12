# DiaryDetailView.swift

## Responsibility

- Present one diary entry, its edit/share/AI controls, and local audio playback state.

## Boundaries

- Audio delegate and timer callbacks must return to the main actor before mutating SwiftUI state.
- Logs must not contain diary text, user-visible error text, or audio paths.

## Behavior Notes

- `AVPlayerDelegate` uses an explicit main-actor task for playback completion.
- The playback timer re-enters the main actor before reading the player or publishing progress.

## Tests

- Strict-concurrency builds cover callback isolation; audio playback remains a manual simulator/device check.
