//
//  AIResponseParser.swift
//  EasyNote
//
//  Created by Codex on 2026/6/11.
//

import Foundation

enum AIResponseParser {
    private struct DiaryAnalysisResponse: Decodable {
        let moods: [String]?
        let tags: [String]?
    }

    private struct RecommendationsResponse: Decodable {
        let recommendations: [String]?
        let todos: [String]?
    }

    static func parseDiaryAnalysis(_ text: String) -> (moods: [String], tags: [String]) {
        for candidate in jsonObjectCandidates(in: text) {
            guard let data = candidate.data(using: .utf8),
                  let response = try? JSONDecoder().decode(DiaryAnalysisResponse.self, from: data) else {
                continue
            }

            let moods = normalizedItems(response.moods)
            let tags = normalizedItems(response.tags)

            if !moods.isEmpty, !tags.isEmpty {
                return (moods: moods, tags: tags)
            }
        }

        return defaultDiaryAnalysis()
    }

    static func parseRecommendations(_ text: String) -> (recommendations: [String], todos: [String]) {
        for candidate in jsonObjectCandidates(in: text) {
            guard let data = candidate.data(using: .utf8),
                  let response = try? JSONDecoder().decode(RecommendationsResponse.self, from: data) else {
                continue
            }

            let recommendations = normalizedItems(response.recommendations)
            let todos = normalizedItems(response.todos)

            if !recommendations.isEmpty, !todos.isEmpty {
                return (recommendations: recommendations, todos: todos)
            }
        }

        let fallbackRecommendations = extractSectionItems(
            from: text,
            startMarkers: ["推荐活动", "推荐", "建议活动", "建议"],
            stopMarkers: ["待办事项", "待办", "任务"]
        )
        let fallbackTodos = extractSectionItems(
            from: text,
            startMarkers: ["待办事项", "待办", "任务"],
            stopMarkers: ["推荐活动", "推荐", "建议"]
        )

        if !fallbackRecommendations.isEmpty || !fallbackTodos.isEmpty {
            let defaults = defaultRecommendations()
            return (
                recommendations: fallbackRecommendations.isEmpty ? defaults.recommendations : fallbackRecommendations,
                todos: fallbackTodos.isEmpty ? defaults.todos : fallbackTodos
            )
        }

        return defaultRecommendations()
    }

    static func defaultDiaryAnalysis() -> (moods: [String], tags: [String]) {
        (moods: ["平静", "思考", "感动"], tags: ["日常", "生活", "随想"])
    }

    static func defaultRecommendations() -> (recommendations: [String], todos: [String]) {
        (
            recommendations: ["花点时间阅读一本书", "尝试冥想15分钟", "进行30分钟的有氧运动", "和朋友或家人联系", "学习一项新技能"],
            todos: ["记录今天的心情和想法", "整理工作计划", "确保充足的水分摄入"]
        )
    }

    private static func jsonObjectCandidates(in text: String) -> [String] {
        var candidates = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        candidates.append(contentsOf: fencedCodeBlocks(in: text))

        if let object = firstBalancedJSONObject(in: text) {
            candidates.append(object)
        }

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .filter { seen.insert($0).inserted }
    }

    private static func fencedCodeBlocks(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"```(?:json|JSON)?\s*([\s\S]*?)```"#,
            options: []
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let contentRange = Range(match.range(at: 1), in: text) else {
                return nil
            }

            return String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func firstBalancedJSONObject(in text: String) -> String? {
        let characters = Array(text)
        var startIndex: Int?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for (index, character) in characters.enumerated() {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(characters[startIndex...index])
                }
            }
        }

        return nil
    }

    private static func normalizedItems(_ items: [String]?) -> [String] {
        items?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func extractSectionItems(
        from text: String,
        startMarkers: [String],
        stopMarkers: [String]
    ) -> [String] {
        var items: [String] = []
        var isCollecting = false

        for line in text.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedLine.isEmpty else {
                if isCollecting {
                    isCollecting = false
                }
                continue
            }

            if containsAnyMarker(trimmedLine, markers: stopMarkers), isCollecting {
                isCollecting = false
                if containsAnyMarker(trimmedLine, markers: startMarkers) {
                    isCollecting = true
                    appendInlineItems(from: trimmedLine, after: startMarkers, into: &items)
                }
                continue
            }

            if containsAnyMarker(trimmedLine, markers: startMarkers) {
                isCollecting = true
                appendInlineItems(from: trimmedLine, after: startMarkers, into: &items)
                continue
            }

            if isCollecting {
                let item = stripListPrefix(from: trimmedLine)
                if !item.isEmpty {
                    items.append(item)
                }
            }
        }

        return items
    }

    private static func appendInlineItems(from line: String, after markers: [String], into items: inout [String]) {
        guard let marker = markers.first(where: { line.contains($0) }),
              let markerRange = line.range(of: marker) else {
            return
        }

        let suffix = line[markerRange.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: ":： "))

        let inlineItems = suffix
            .components(separatedBy: CharacterSet(charactersIn: "，,；;、"))
            .map(stripListPrefix)
            .filter { !$0.isEmpty }

        items.append(contentsOf: inlineItems)
    }

    private static func containsAnyMarker(_ text: String, markers: [String]) -> Bool {
        markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func stripListPrefix(from text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*(?:[-*+•]|\d+[\.\)、）]?)\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
