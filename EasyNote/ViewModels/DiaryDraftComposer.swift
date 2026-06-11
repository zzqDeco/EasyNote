//
//  DiaryDraftComposer.swift
//  EasyNote
//
//  Created by Codex on 2026/6/11.
//

import Foundation

enum DiaryTranscriptionApplyMode {
    case insert
    case replace
}

enum DiaryDraftComposer {
    static func apply(
        transcription: String,
        to content: String,
        mode: DiaryTranscriptionApplyMode
    ) -> String {
        let normalizedTranscription = transcription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTranscription.isEmpty else {
            return content
        }

        switch mode {
        case .replace:
            return normalizedTranscription
        case .insert:
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return normalizedTranscription
            }

            return "\(content)\n\n\(normalizedTranscription)"
        }
    }
}

struct VoiceRecordingDraft {
    let audioURL: URL?
    let transcription: String
}
