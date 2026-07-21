import Testing
@testable import TelemetryKit

/// ADR-0012 §Decision.3: `DiagnosticSanitizer` is the mandatory chokepoint
/// before any crash/hang stack reaches the third-party transport. These tests
/// lock the allow-list behavior adversarially — anything shaped like free-form
/// user text, a HealthKit value, or PII must be REJECTED WHOLE (not partially
/// stripped), while legitimate symbolication frames survive verbatim.
@Suite("DiagnosticSanitizer")
struct DiagnosticSanitizerTests {

    // MARK: - Frame allow-list

    @Test("keeps a canonical symbolication frame verbatim")
    func keepsCanonicalFrame() {
        let frame = "VitalStride ExercisePickerView.applyVisibleEquipment(_:) +128"
        #expect(DiagnosticSanitizer.sanitizeFrame(frame) == frame)
    }

    @Test("keeps a mangled Swift symbol with generics/parens")
    func keepsMangledSymbol() {
        let frame = "VitalStride closure #1 in ExercisePickerView.body.getter +44"
        #expect(DiagnosticSanitizer.sanitizeFrame(frame) == frame)
    }

    @Test("rejects a frame containing non-ASCII (e.g. leaked localized text)")
    func rejectsNonASCIIFrame() {
        // A stack should never contain CJK; if it does, drop the whole frame
        // rather than forward a fragment.
        #expect(DiagnosticSanitizer.sanitizeFrame("动作 selection 卧推") == nil)
    }

    @Test("rejects a frame that looks like a health value string")
    func rejectsHealthValueShape() {
        // Defensive: a heart-rate/weight string would carry '=' or other
        // disallowed bytes, or non-ASCII units — rejected whole.
        #expect(DiagnosticSanitizer.sanitizeFrame("heartRate=172bpm") == nil)
        #expect(DiagnosticSanitizer.sanitizeFrame("bodyWeight=83.5kg@2026") == nil)
    }

    @Test("rejects a frame with an email / PII shape")
    func rejectsPIIShape() {
        // '@' is not in the allow-list; an email cannot pass.
        #expect(DiagnosticSanitizer.sanitizeFrame("user 1105208297@qq.com") == nil)
    }

    @Test("rejects control characters and quotes")
    func rejectsControlAndQuotes() {
        #expect(DiagnosticSanitizer.sanitizeFrame("frame\u{0007}bell") == nil)
        #expect(DiagnosticSanitizer.sanitizeFrame("say \"hi\"") == nil)
    }

    @Test("rejects empty / whitespace-only frames")
    func rejectsEmpty() {
        #expect(DiagnosticSanitizer.sanitizeFrame("") == nil)
        #expect(DiagnosticSanitizer.sanitizeFrame("   \n\t") == nil)
    }

    @Test("trims surrounding whitespace but keeps inner spacing")
    func trimsOuterWhitespace() {
        #expect(DiagnosticSanitizer.sanitizeFrame("  Foo.bar() +8  ") == "Foo.bar() +8")
    }

    @Test("rejects an over-long frame")
    func rejectsOverLongFrame() {
        let huge = String(repeating: "a", count: DiagnosticSanitizer.maxFrameLength + 1)
        #expect(DiagnosticSanitizer.sanitizeFrame(huge) == nil)
    }

    // MARK: - Frame list

    @Test("drops rejected frames but keeps valid ones, order preserved")
    func filtersListPreservingOrder() {
        let raw = [
            "VitalStride A.f() +0",
            "user 卧推",              // rejected
            "VitalStride B.g() +16",
            "leak=heart_rate_172",   // rejected ('=')
            "VitalStride C.h() +32",
        ]
        let out = DiagnosticSanitizer.sanitizeFrames(raw)
        #expect(out == ["VitalStride A.f() +0", "VitalStride B.g() +16", "VitalStride C.h() +32"])
    }

    @Test("caps the frame count at maxFrames")
    func capsFrameCount() {
        let raw = (0..<(DiagnosticSanitizer.maxFrames + 50)).map { "VitalStride f\($0)() +0" }
        let out = DiagnosticSanitizer.sanitizeFrames(raw)
        #expect(out.count == DiagnosticSanitizer.maxFrames)
        // Truncation keeps the TOP of the stack (the actionable crashing frames).
        #expect(out.first == "VitalStride f0() +0")
    }

    // MARK: - Version metadata

    @Test("keeps a dotted version string")
    func keepsVersion() {
        #expect(DiagnosticSanitizer.sanitizeVersion("26.5.2") == "26.5.2")
        #expect(DiagnosticSanitizer.sanitizeVersion("5") == "5")
    }

    @Test("maps non-numeric version junk to unknown")
    func versionJunkToUnknown() {
        #expect(DiagnosticSanitizer.sanitizeVersion("iOS 卧推") == "unknown")
        #expect(DiagnosticSanitizer.sanitizeVersion("") == "unknown")
        #expect(DiagnosticSanitizer.sanitizeVersion("26.5; rm -rf") == "unknown")
    }

    // MARK: - Termination reason

    @Test("keeps a canonical exception token")
    func keepsExceptionToken() {
        #expect(DiagnosticSanitizer.sanitizeTerminationReason("EXC_BAD_ACCESS") == "EXC_BAD_ACCESS")
        #expect(DiagnosticSanitizer.sanitizeTerminationReason("SIGABRT") == "SIGABRT")
    }

    @Test("rejects a termination reason with free-form text")
    func rejectsFreeFormReason() {
        #expect(DiagnosticSanitizer.sanitizeTerminationReason("crashed while 卧推") == nil)
        #expect(DiagnosticSanitizer.sanitizeTerminationReason("addr=0xdeadbeef") == nil)
    }

    @Test("nil reason stays nil")
    func nilReason() {
        #expect(DiagnosticSanitizer.sanitizeTerminationReason(nil) == nil)
    }
}
