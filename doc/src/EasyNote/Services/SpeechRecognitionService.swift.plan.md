# SpeechRecognitionService.swift

## Responsibility

- Own speech-recognition and microphone permission requests.
- Manage `AVAudioEngine`, recognition requests, recording state, and transcribed text publication.
- Provide a single save hook returning the current audio URL and transcription.

## Boundaries

- Views should not manage `AVAudioEngine` or `SFSpeechAudioBufferRecognitionRequest`.
- Diary persistence belongs in `DiaryViewModel`, not this service.

## Behavior Notes

- Speech recognition locale is currently `zh-CN`.
- Recording state and transcription changes are also broadcast through `NotificationCenter`.
- `saveRecordingWithTranscription()` validates that the recording URL exists before returning it.

## Tests

- Permission and recording behavior requires manual device/simulator verification.
- ViewModel tests should mock this service after dependency injection is introduced.
