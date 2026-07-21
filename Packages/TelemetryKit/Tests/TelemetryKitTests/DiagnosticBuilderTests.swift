import Testing
@testable import TelemetryKit

/// ADR-0012: `DiagnosticBuilder` is the assembly point where MetricKit-extracted
/// primitives become a sanitized `TelemetryDiagnostic`. Tests confirm every
/// field is sanitized and that a stack which sanitizes to nothing is dropped.
@Suite("DiagnosticBuilder")
struct DiagnosticBuilderTests {

    @Test("assembles a hang diagnostic with sanitized fields")
    func assemblesHang() {
        let diag = DiagnosticBuilder.make(
            kind: .hang,
            rawOSVersion: "26.5.2",
            rawAppBuild: "5",
            rawFrames: ["VitalStride ExercisePickerView.body +12", "VitalStride A.f() +0"]
        )
        #expect(diag != nil)
        #expect(diag?.kind == .hang)
        #expect(diag?.osVersion == "26.5.2")
        #expect(diag?.appBuild == "5")
        #expect(diag?.frames.count == 2)
        #expect(diag?.terminationReason == nil)
    }

    @Test("drops frames that fail sanitization but keeps the diagnostic")
    func dropsBadFrames() {
        let diag = DiagnosticBuilder.make(
            kind: .crash,
            rawOSVersion: "26.5",
            rawAppBuild: "5",
            rawFrames: ["VitalStride Good.f() +0", "user 卧推 1105208297@qq.com"],
            rawTerminationReason: "EXC_BAD_ACCESS"
        )
        #expect(diag?.frames == ["VitalStride Good.f() +0"])
        #expect(diag?.terminationReason == "EXC_BAD_ACCESS")
    }

    @Test("returns nil when no frame survives sanitization")
    func nilWhenNoUsableFrames() {
        let diag = DiagnosticBuilder.make(
            kind: .hang,
            rawOSVersion: "26.5",
            rawAppBuild: "5",
            rawFrames: ["卧推", "heartRate=172", ""]
        )
        #expect(diag == nil)
    }

    @Test("junk metadata is neutralized, not propagated")
    func neutralizesJunkMetadata() {
        let diag = DiagnosticBuilder.make(
            kind: .crash,
            rawOSVersion: "iOS twenty-six",
            rawAppBuild: "build 5; rm -rf",
            rawFrames: ["VitalStride Z.y() +8"],
            rawTerminationReason: "crashed doing 卧推"
        )
        #expect(diag?.osVersion == "unknown")
        #expect(diag?.appBuild == "unknown")
        #expect(diag?.terminationReason == nil)  // free-form reason rejected
        #expect(diag?.frames == ["VitalStride Z.y() +8"])
    }
}

/// ADR-0012 §Decision.3 / codex review: the `TelemetryDiagnostic` initializer
/// is public, so it must itself enforce sanitization — an external caller must
/// not be able to construct one carrying free-form strings / health values and
/// hand it to a provider, bypassing `DiagnosticBuilder`. These tests lock that
/// the init sanitizes every field.
@Suite("TelemetryDiagnostic init sanitization")
struct TelemetryDiagnosticInitTests {

    @Test("direct init sanitizes dirty frames (closes the bypass)")
    func initSanitizesFrames() {
        let diag = TelemetryDiagnostic(
            kind: .hang,
            osVersion: "26.5",
            appBuild: "5",
            frames: [
                "VitalStride Good.f() +0",  // clean symbolication frame — kept
                "heartRate=172bpm",          // '=' → rejected whole
                "user 卧推",                 // non-ASCII → rejected whole
            ]
        )
        // Only the clean frame survives; frames carrying disallowed bytes
        // (separators / non-ASCII — the shapes leaked user text or a health
        // key=value would take) are dropped whole by the init-time sanitizer.
        #expect(diag.frames == ["VitalStride Good.f() +0"])
    }

    @Test("direct init neutralizes junk metadata and reason")
    func initSanitizesMetadata() {
        let diag = TelemetryDiagnostic(
            kind: .crash,
            osVersion: "iOS 卧推",
            appBuild: "build; rm -rf",
            frames: ["VitalStride Z.y() +8"],
            terminationReason: "crashed 卧推"
        )
        #expect(diag.osVersion == "unknown")
        #expect(diag.appBuild == "unknown")
        #expect(diag.terminationReason == nil)
    }

    @Test("already-clean input passes through unchanged (idempotent)")
    func initIsIdempotentOnCleanInput() {
        let diag = TelemetryDiagnostic(
            kind: .crash,
            osVersion: "26.5.2",
            appBuild: "5",
            frames: ["VitalStride A.f() +0", "VitalStride B.g() +16"],
            terminationReason: "EXC_BAD_ACCESS"
        )
        #expect(diag.osVersion == "26.5.2")
        #expect(diag.appBuild == "5")
        #expect(diag.frames == ["VitalStride A.f() +0", "VitalStride B.g() +16"])
        #expect(diag.terminationReason == "EXC_BAD_ACCESS")
    }
}
