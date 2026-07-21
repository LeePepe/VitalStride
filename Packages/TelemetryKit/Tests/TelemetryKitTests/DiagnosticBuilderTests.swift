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
