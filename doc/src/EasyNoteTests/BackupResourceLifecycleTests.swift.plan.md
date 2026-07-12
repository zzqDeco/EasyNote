# BackupResourceLifecycleTests.swift

## Responsibility

- Verify backup resource limits, async execution boundaries, V1 compatibility, and the two-phase audio/SwiftData import lifecycle.

## Boundaries

- Use in-memory SwiftData containers, temporary directories, small injected limits, and deterministic UUIDs.
- Do not read user Documents data or depend on live services, permissions, CloudKit, AI providers, or speech recognition.

## Behavior Notes

- Exact boundaries pass and one-over values fail for raw file bytes, every entity count, one audio asset, total audio bytes, and audio-asset count.
- Injected file and save failures prove prior destination bytes and SwiftData values are restored.
- Cleanup tests distinguish referenced managed recordings from unreferenced managed files, arbitrary files, nested files, and unsupported extensions.

## Tests

- Compile through the `EasyNoteTests` target and run with a simulator runtime compatible with the selected Xcode SDK.
