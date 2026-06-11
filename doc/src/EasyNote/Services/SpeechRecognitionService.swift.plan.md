# SpeechRecognitionService.swift

## Responsibility

- Own speech-recognition and microphone permission requests.
- Manage `AVAudioEngine`, recognition requests, local recording file writing, recording state, and transcribed text publication.
- Publish speech and microphone permission state for UI display.
- Provide a single save hook returning the current audio URL and transcription.

## Boundaries

- Views should not manage `AVAudioEngine` or `SFSpeechAudioBufferRecognitionRequest`.
- Diary persistence belongs in `DiaryViewModel`, not this service.

## Behavior Notes

- Speech recognition locale is currently `zh-CN`.
- Recording state and transcription changes are also broadcast through `NotificationCenter`.
- `startRecording()` should request first-run permissions without auto-starting recording from the permission callback.
- Audio buffers are written to a local recording file while they are also streamed to speech recognition.
- File creation, buffer-write, and audio-engine startup failures tear down the audio engine, input tap, recognition request, and recognition task before reporting the error.
- Audio-engine startup failure should discard the just-created local recording file before returning the error.
- `saveRecordingWithTranscription()` validates that the recording URL exists before returning it, then clears service ownership of that URL so the diary flow owns later cleanup.
- `startRecording()` should discard any stale unclaimed local recording file before creating a new recording.
- Recognition completion callbacks should not overwrite an existing recording error with a finished state after teardown/cancellation.
- Recognition completion callbacks must verify their session token before publishing text, finishing state, or tearing down the active audio pipeline.

## Tests

- Permission and recording behavior requires manual device/simulator verification.
- Pure draft-composition tests cover applying transcription text without requiring microphone access.
