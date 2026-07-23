import Testing
@testable import TelemetryKit

/// spec 015-glitchtip-crash-reporting §T001: `CrashEventSanitizer` is the
/// TelemetryKit-side, Sentry-free chokepoint that a third-party crash SDK's
/// `beforeSend` callback must go through before the event leaves the device.
///
/// These tests are adversarial: any raw event carrying free-form user text,
/// a HealthKit value (heart rate, weight), PII (email, IP), or an unmodeled
/// SDK bag (extra/contexts/breadcrumbs/tags/request) must cause the WHOLE
/// event to be rejected (`nil`), never a partially-scrubbed pass-through.
/// Only allow-listed shapes (canonical symbolication frames + coarse OS/app
/// metadata) may survive. Locks Constitution §I and ADR-0012 §Decision.3.
@Suite("CrashEventSanitizer")
struct CrashEventSanitizerTests {

    // MARK: - Baseline: a well-formed crash event passes through

    @Test("keeps a legitimate crash event with clean frames + coarse metadata")
    func keepsLegitimateCrashEvent() {
        let raw = RawCrashEvent(
            message: nil,
            frames: [
                "VitalStride ExercisePickerView.applyVisibleEquipment(_:) +128",
                "VitalStride closure #1 in ExercisePickerView.body.getter +44",
            ],
            osVersion: "26.5.2",
            appBuild: "5",
            terminationReason: "EXC_BAD_ACCESS"
        )
        let clean = CrashEventSanitizer.sanitize(raw)
        #expect(clean != nil)
        #expect(clean?.kind == .crash)
        #expect(clean?.osVersion == "26.5.2")
        #expect(clean?.appBuild == "5")
        #expect(clean?.terminationReason == "EXC_BAD_ACCESS")
        #expect(clean?.frames.count == 2)
    }

    @Test("honors an explicit .hang kind")
    func honorsHangKind() {
        let raw = RawCrashEvent(
            frames: ["VitalStride RunLoop.tick() +12"],
            osVersion: "26.5.2",
            appBuild: "5"
        )
        let clean = CrashEventSanitizer.sanitize(raw, kind: .hang)
        #expect(clean?.kind == .hang)
    }

    @Test("allows an opaque anonymised user id (uuid-shaped)")
    func allowsOpaqueUserId() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            user: RawUser(id: "3F9A2C88-3C29-4B4E-8B0F-89F1C4A2A7DE")
        )
        #expect(CrashEventSanitizer.sanitize(raw) != nil)
    }

    // MARK: - Health-value payloads (§I)

    @Test("rejects an event whose `extra` carries a heart-rate value")
    func rejectsHeartRateInExtra() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            extra: ["heartRate": "172"]
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `extra` carries a body weight value")
    func rejectsWeightInExtra() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            extra: ["bodyMassKg": "78.4"]
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `contexts` carries a health context bag")
    func rejectsHealthContexts() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            contexts: ["health": ["heartRate": "172", "hrv": "43"]]
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `tags` carries a health tag")
    func rejectsHealthTag() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            tags: ["heartRate": "172"]
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    // MARK: - PII payloads

    @Test("rejects an event whose `user.email` is set")
    func rejectsUserEmail() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            user: RawUser(id: nil, email: "user@example.com")
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `user.username` is set")
    func rejectsUsername() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            user: RawUser(username: "leepepe")
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `user.ipAddress` is set")
    func rejectsIPAddress() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            user: RawUser(ipAddress: "10.0.0.5")
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `user.name` is set")
    func rejectsUserName() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            user: RawUser(name: "Li Pei")
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `user.id` is not a short opaque token")
    func rejectsFreeformUserId() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            user: RawUser(id: "user@example.com")
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event whose `extra` carries an email string")
    func rejectsEmailInExtra() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            extra: ["contact": "user@example.com"]
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    // MARK: - Free-form text payloads

    @Test("rejects an event whose `message` is a full sentence")
    func rejectsSentenceMessage() {
        let raw = RawCrashEvent(
            message: "User Li Pei's workout crashed at rep 5",
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5"
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("accepts a canonical short-token message (exception code)")
    func acceptsShortTokenMessage() {
        let raw = RawCrashEvent(
            message: "SIGABRT",
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5"
        )
        #expect(CrashEventSanitizer.sanitize(raw) != nil)
    }

    @Test("rejects an event with a populated breadcrumb list")
    func rejectsBreadcrumbs() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            breadcrumbs: ["user tapped Save on Workout"]
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("rejects an event with a populated request bag")
    func rejectsRequestBag() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5",
            request: ["url": "https://api.example.com/user/42"]
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    // MARK: - Frame-level chokepoint reuse

    @Test("rejects an event whose frames all fail the DiagnosticSanitizer allow-list")
    func rejectsAllInvalidFrames() {
        let raw = RawCrashEvent(
            frames: ["动作 selection 卧推", "heartRate 172bpm"],
            osVersion: "26.5.2",
            appBuild: "5"
        )
        #expect(CrashEventSanitizer.sanitize(raw) == nil)
    }

    @Test("keeps only the frames that pass DiagnosticSanitizer, drops the rest")
    func keepsOnlyValidFrames() {
        let raw = RawCrashEvent(
            frames: [
                "VitalStride ExercisePickerView.body.getter +44",  // valid
                "heartRate 172bpm",                                 // rejected
                "VitalStride main +0",                              // valid
            ],
            osVersion: "26.5.2",
            appBuild: "5"
        )
        let clean = CrashEventSanitizer.sanitize(raw)
        #expect(clean?.frames.count == 2)
        #expect(clean?.frames.contains("VitalStride ExercisePickerView.body.getter +44") == true)
        #expect(clean?.frames.contains("VitalStride main +0") == true)
    }

    // MARK: - Metadata normalization is idempotent through TelemetryDiagnostic

    @Test("adversarial appBuild is normalized to 'unknown' sentinel, event not smuggled")
    func adversarialAppBuildBecomesUnknown() {
        let raw = RawCrashEvent(
            frames: ["VitalStride main +0"],
            osVersion: "26.5.2",
            appBuild: "5; heartRate=172"
        )
        let clean = CrashEventSanitizer.sanitize(raw)
        // The event is not rejected at the sanitizer level (metadata is on
        // the allow-list, not the reject-whole-event list) — but the
        // `TelemetryDiagnostic` initializer refuses the adversarial build
        // string and substitutes the "unknown" sentinel, so the heartRate
        // value never actually reaches the transport.
        #expect(clean?.appBuild == "unknown")
    }
}
