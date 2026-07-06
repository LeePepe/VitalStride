import Foundation
import VitalModels

struct SubstituteRequest: Sendable, Equatable {
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Equipment
}

struct SubstituteSuggestion: Sendable, Codable, Equatable {
    let exerciseId: String
    let reason: String
}

enum SubstituteParseError: Error, Equatable {
    case invalidJSON
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
