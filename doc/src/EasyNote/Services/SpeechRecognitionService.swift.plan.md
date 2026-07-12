# SpeechRecognitionService.swift

## Responsibility

- Own speech-recognition and microphone permission requests.
- Manage `AVAudioEngine`, recognition requests, local recording file writing, recording state, and transcribed text publication.
- Publish speech and microphone permission state for UI display.
- Provide a single save hook returning the current audio URL and transcription.

## Boundaries

- Views should not manage `AVAudioEngine` or `SFSpeechAudioBufferRecognitionRequest`.
- Diary persistence belongs in `DiaryViewModel`, not this service.
- Published state and audio-engine lifecycle methods are main-actor isolated; framework callbacks must not mutate service state directly.

## Behavior Notes

- Speech recognition locale is currently `zh-CN`.
- Recording state and transcription changes are also broadcast through `NotificationCenter`.
- `startRecording()` should request first-run permissions without auto-starting recording from the permission callback.
- Audio buffers are written to a local recording file while they are also streamed to speech recognition.
- File creation, buffer-write, and audio-engine startup failures tear down the audio engine, input tap, recognition request, and recognition task before reporting the error.
- Audio-engine startup failure should discard the just-created local recording file before returning the error.
- `saveRecordingWithTranscription()` validates that the recording URL exists before returning it, then clears service ownership of that URL so the diary flow owns later cleanup.
- `startRecording()` should discard any stale unclaimed local recording file before creating a new recording.
- `cancelRecording()` invalidates and cancels recognition, deletes the unclaimed recording, and clears transcription so late callbacks cannot leak discarded text into another editor.
- Recognition completion callbacks should not overwrite an existing recording error with a finished state after teardown/cancellation.
- Recognition completion callbacks must verify their session token before publishing text, finishing state, or tearing down the active audio pipeline.
- A lock-protected session gate allows only one active recognition token. A second start is rejected, and teardown invalidates the token before recognition cancellation or input-tap removal.
- A new start may cancel a stopped session that is still waiting for a final Speech callback; only an actively recording session blocks replacement.
- Each input tap captures its own recognition request and audio file, checks the gate before use, and hops failures to the main actor for serialized teardown.
- Speech and microphone permission callbacks return to the main actor before changing published status or invoking the caller completion.
- Unified logging records only permission outcomes and static lifecycle/failure events; it never records transcription text or recording paths.

## Tests

- Pure session-gate tests cover overlap rejection, invalidation, and late-callback rejection.
- Permission and live recording behavior requires manual device/simulator verification.
- Pure draft-composition tests cover applying transcription text without requiring microphone access.
