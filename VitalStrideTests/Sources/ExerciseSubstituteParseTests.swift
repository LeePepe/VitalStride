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
}
