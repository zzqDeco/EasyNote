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
- `saveRecordingWithTranscription()` validates that the recording URL exists before returning it.

## Tests

- Permission and recording behavior requires manual device/simulator verification.
- Pure draft-composition tests cover applying transcription text without requiring microphone access.
