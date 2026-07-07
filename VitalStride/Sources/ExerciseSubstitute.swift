import AIService
import Foundation
import VitalModels

struct SubstituteRequest: Sendable, Equatable {
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Equipment
}

enum SubstitutePromptBuilder {
    static let requestedCount = 3

    static func build(for request: SubstituteRequest) -> [ChatMessage] {
        let muscle = request.muscleGroup.rawValue
        let equipment = request.equipment.rawValue

        let systemContent = """
            You are a strength-training assistant recommending substitute exercises.
            Constraints:
            - Recommend exactly \(requestedCount) substitutes for the given exercise.
            - Every substitute MUST target the same primary muscle group as the current exercise.
            - Never recommend the current exercise itself.
            - Prefer substitutes usable with the listed equipment when reasonable, but same primary muscle is required.
            - Respond with a single JSON array only, no prose, no markdown fences.
            - Each array element MUST have exactly two string fields: "exerciseId" and "reason".
            - "exerciseId" is a short stable identifier for the substitute exercise (kebab-case, ASCII).
            - "reason" is a concise Chinese explanation of why it substitutes (<= 40 characters), no health metrics.
            """

        let userContent = """
            当前动作:
            - 名称: \(request.name)
            - 主肌群: \(muscle)
            - 器械: \(equipment)

            请返回 \(requestedCount) 个同主肌群 (\(muscle)) 的替代动作，排除当前动作本身。
            仅输出 JSON 数组，形如: [{"exerciseId":"...","reason":"..."}]
            """

        return [
            ChatMessage(role: "system", content: systemContent),
            ChatMessage(role: "user", content: userContent),
        ]
    }
}

struct SubstituteSuggestion: Sendable, Codable, Equatable {
    let exerciseId: String
    let reason: String
}

enum SubstituteParseError: Error, Equatable {
    case invalidJSON
}

/// Deterministic post-resolution validator for substitute candidates.
///
/// SC-002 requires every substitute to target the same primary muscle group
/// as the current exercise. The AI prompt asks for this, but prompt-only
/// enforcement is unreliable — a valid preset id from another muscle group
/// would otherwise be displayed as if it matched. This filter is the
/// deterministic guard the resolve path runs after each suggestion is
/// resolved to a local `Exercise`.
enum SubstituteRecommendationFilter {
    /// Returns true iff the resolved exercise's muscle group equals `expected`.
    /// Callers drop suggestions whose resolved exercise fails this check.
    static func acceptsSameMuscleGroup(
        exerciseMuscleGroup: MuscleGroup,
        expected: MuscleGroup
    ) -> Bool {
        exerciseMuscleGroup == expected
    }
}

extension SubstituteSuggestion {
    /// Parses an AI substitute-suggestion response formatted as `[{"exerciseId": ..., "reason": ...}]`.
    ///
    /// - Parameters:
    ///   - raw: Raw AI response text. Surrounding whitespace and a single markdown
    ///     code fence (```` ```json ... ``` ```` or ```` ``` ... ``` ````) are tolerated.
    ///   - excludingExerciseId: If non-nil, suggestions whose `exerciseId` equals this
    ///     value are filtered out (used to drop the current exercise from its own
    ///     substitute list). Order of remaining entries is preserved.
    /// - Returns: Parsed suggestions in original order. May be empty or fewer than
    ///   any requested count; callers decide how to handle short lists.
    /// - Throws: `SubstituteParseError.invalidJSON` when the input cannot be decoded
    ///   as the expected array shape. Never crashes on malformed input.
    static func parse(
        from raw: String,
        excluding excludingExerciseId: String? = nil
    ) throws -> [SubstituteSuggestion] {
        let cleaned = stripCodeFence(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw SubstituteParseError.invalidJSON
        }
        let decoded: [SubstituteSuggestion]
        do {
            decoded = try JSONDecoder().decode([SubstituteSuggestion].self, from: data)
        } catch {
            throw SubstituteParseError.invalidJSON
        }
        guard let excluded = excludingExerciseId else {
            return decoded
        }
        return decoded.filter { $0.exerciseId != excluded }
    }

    private static func stripCodeFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        if let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        } else {
            text = String(text.dropFirst(3))
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
