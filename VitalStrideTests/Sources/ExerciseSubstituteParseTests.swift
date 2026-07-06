import Foundation
import Testing

@testable import VitalStride

@Suite("Exercise Substitute JSON Parser Tests")
struct ExerciseSubstituteParseTests {

    @Test("Valid JSON with exactly 3 entries decodes all suggestions in order")
    func validThreeEntryJSONDecodesAll() throws {
        let raw = """
            [
              {"exerciseId": "incline-db-press", "reason": "同为上胸推举，器械可替换"},
              {"exerciseId": "cable-fly", "reason": "同主肌群胸，器械不同"},
              {"exerciseId": "push-up", "reason": "自重同肌群备选"}
            ]
            """

        let result = try SubstituteSuggestion.parse(from: raw)

        #expect(result.count == 3)
        #expect(result[0].exerciseId == "incline-db-press")
        #expect(result[0].reason == "同为上胸推举，器械可替换")
        #expect(result[1].exerciseId == "cable-fly")
        #expect(result[2].exerciseId == "push-up")
    }

    @Test("Valid JSON wrapped in a markdown code fence still decodes")
    func validJSONInsideMarkdownFenceDecodes() throws {
        let raw = """
            ```json
            [
              {"exerciseId": "incline-db-press", "reason": "同为上胸推举"},
              {"exerciseId": "cable-fly", "reason": "同肌群不同器械"},
              {"exerciseId": "push-up", "reason": "自重替代"}
            ]
            ```
            """

        let result = try SubstituteSuggestion.parse(from: raw)

        #expect(result.count == 3)
        #expect(result.map(\.exerciseId) == ["incline-db-press", "cable-fly", "push-up"])
    }

    @Test("Malformed non-JSON input throws invalidJSON without crashing")
    func malformedInputThrowsInvalidJSON() {
        let raw = "this is not json at all — 抱歉"

        #expect(throws: SubstituteParseError.invalidJSON) {
            _ = try SubstituteSuggestion.parse(from: raw)
        }
    }

    @Test("JSON object (non-array) at the top level throws invalidJSON")
    func nonArrayJSONThrowsInvalidJSON() {
        let raw = """
            {"exerciseId": "cable-fly", "reason": "同肌群不同器械"}
            """

        #expect(throws: SubstituteParseError.invalidJSON) {
            _ = try SubstituteSuggestion.parse(from: raw)
        }
    }

    @Test("Array with missing required fields throws invalidJSON")
    func arrayWithMissingFieldsThrowsInvalidJSON() {
        let raw = """
            [
              {"exerciseId": "incline-db-press"},
              {"reason": "缺少 exerciseId"}
            ]
            """

        #expect(throws: SubstituteParseError.invalidJSON) {
            _ = try SubstituteSuggestion.parse(from: raw)
        }
    }

    @Test("Fewer than 3 candidates returns the actual count, no padding")
    func fewerThanThreeCandidatesReturnedAsIs() throws {
        let raw = """
            [
              {"exerciseId": "incline-db-press", "reason": "同为上胸推举"},
              {"exerciseId": "cable-fly", "reason": "同肌群不同器械"}
            ]
            """

        let result = try SubstituteSuggestion.parse(from: raw)

        #expect(result.count == 2)
        #expect(result.map(\.exerciseId) == ["incline-db-press", "cable-fly"])
    }

    @Test("Empty JSON array returns empty result without throwing")
    func emptyArrayReturnsEmpty() throws {
        let result = try SubstituteSuggestion.parse(from: "[]")

        #expect(result.isEmpty)
    }

    @Test("Self-reference to the current exercise is filtered out")
    func selfReferenceIsFiltered() throws {
        let raw = """
            [
              {"exerciseId": "bench-press", "reason": "同肌群，禁止返回但仍应过滤"},
              {"exerciseId": "incline-db-press", "reason": "同为上胸推举"},
              {"exerciseId": "cable-fly", "reason": "同肌群不同器械"}
            ]
            """

        let result = try SubstituteSuggestion.parse(from: raw, excluding: "bench-press")

        #expect(result.count == 2)
        #expect(result.contains { $0.exerciseId == "bench-press" } == false)
        #expect(result.map(\.exerciseId) == ["incline-db-press", "cable-fly"])
    }

    @Test("Self-reference filter preserves order of remaining entries")
    func selfReferenceFilterPreservesOrder() throws {
        let raw = """
            [
              {"exerciseId": "a", "reason": "r1"},
              {"exerciseId": "b", "reason": "r2"},
              {"exerciseId": "a", "reason": "r3"},
              {"exerciseId": "c", "reason": "r4"}
            ]
            """

        let result = try SubstituteSuggestion.parse(from: raw, excluding: "a")

        #expect(result.map(\.exerciseId) == ["b", "c"])
    }

    @Test("Nil exclusion returns all entries unchanged")
    func nilExclusionReturnsAll() throws {
        let raw = """
            [
              {"exerciseId": "bench-press", "reason": "same"},
              {"exerciseId": "incline-db-press", "reason": "diff"}
            ]
            """

        let result = try SubstituteSuggestion.parse(from: raw, excluding: nil)

        #expect(result.count == 2)
        #expect(result.map(\.exerciseId) == ["bench-press", "incline-db-press"])
    }

    // MARK: - T010 Fallback reachability (SC-003, Bar D)
    //
    // These tests assert the caller can OBSERVE a fallback condition — either
    // a catchable `SubstituteParseError` (AI/JSON failure path) or an empty
    // `[SubstituteSuggestion]` (zero effective candidates path) — so upstream
    // code (`ExerciseSubstituteSheet`) can graceful-degrade to the manual
    // `ExercisePickerView`. The parser MUST NOT crash, MUST NOT silently
    // succeed, and MUST expose these signals deterministically without any
    // network / AI provider / HealthKit dependency.

    @Test("AI-unavailable simulated by empty response surfaces catchable fallback error")
    func aiUnavailableEmptyResponseIsCatchableFallbackSignal() {
        let raw = ""

        var caught: SubstituteParseError?
        do {
            _ = try SubstituteSuggestion.parse(from: raw)
        } catch let error as SubstituteParseError {
            caught = error
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(caught == .invalidJSON)
    }

    @Test("AI-unavailable simulated by whitespace-only response surfaces catchable fallback error")
    func aiUnavailableWhitespaceResponseIsCatchableFallbackSignal() {
        let raw = "   \n\t  \n"

        #expect(throws: SubstituteParseError.invalidJSON) {
            _ = try SubstituteSuggestion.parse(from: raw)
        }
    }

    @Test("AI garbled response surfaces catchable fallback error, never crashes")
    func aiGarbledResponseIsCatchableFallbackSignal() {
        let raw = "<html>503 Service Unavailable</html>"

        #expect(throws: SubstituteParseError.invalidJSON) {
            _ = try SubstituteSuggestion.parse(from: raw)
        }
    }

    @Test("Truncated JSON array surfaces catchable fallback error, never crashes")
    func truncatedJSONIsCatchableFallbackSignal() {
        let raw = """
            [
              {"exerciseId": "incline-db-press", "reason": "同为上胸推举"},
              {"exerciseId": "cable-fly"
            """

        #expect(throws: SubstituteParseError.invalidJSON) {
            _ = try SubstituteSuggestion.parse(from: raw)
        }
    }

    @Test("Empty effective candidates after exclusion returns empty array as observable fallback signal")
    func emptyEffectiveCandidatesAfterExclusionIsObservableFallbackSignal() throws {
        let raw = """
            [
              {"exerciseId": "bench-press", "reason": "同肌群但等于当前动作"},
              {"exerciseId": "bench-press", "reason": "重复的当前动作"}
            ]
            """

        let result = try SubstituteSuggestion.parse(from: raw, excluding: "bench-press")

        #expect(result.isEmpty)
    }

    @Test("Empty JSON array returns empty result — observable fallback signal, not silent success")
    func emptyJSONArrayIsObservableFallbackSignal() throws {
        let result = try SubstituteSuggestion.parse(from: "[]", excluding: "bench-press")

        #expect(result.isEmpty)
    }

    @Test("Repeated parse of malformed input does not crash and remains deterministic")
    func repeatedMalformedParseStaysDeterministic() {
        let raw = "not json"
        var errorCount = 0
        for _ in 0..<8 {
            do {
                _ = try SubstituteSuggestion.parse(from: raw)
            } catch SubstituteParseError.invalidJSON {
                errorCount += 1
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }

        #expect(errorCount == 8)
    }

    @Test("Fallback error is a distinguishable SubstituteParseError, not a generic Swift error")
    func fallbackErrorIsDistinguishableType() {
        let raw = "definitely not json"

        do {
            _ = try SubstituteSuggestion.parse(from: raw)
            Issue.record("Expected parse to throw for malformed input")
        } catch let error as SubstituteParseError {
            #expect(error == .invalidJSON)
        } catch {
            Issue.record("Expected SubstituteParseError, got: \(type(of: error))")
        }
    }
}
