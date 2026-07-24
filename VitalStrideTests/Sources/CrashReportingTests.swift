import Foundation
import Sentry
import Testing

@testable import VitalStride

/// spec 015-glitchtip-crash-reporting (MY-1311/T002). Exercises the
/// `CrashReporting` app-side adapter that converts sentry-cocoa `Event`
/// values into TelemetryKit's `RawCrashEvent` intermediate and back through
/// the `CrashEventSanitizer` chokepoint.
///
/// Coverage matrix (all P0):
///   * Fail-safe no-op (§I of DoR acceptance criteria #4)
///       - DEBUG build → `start(bundle:)` returns; SDK stays disabled.
///       - Empty `GlitchTipDSN` in bundle → `_startRelease` returns; SDK stays disabled.
///   * Adversarial input rejection (§I; DoR acceptance #6, 7 categories)
///       - extra / context / breadcrumb / request / tags / user / message
///   * Allow-list retention on a clean crash event (DoR acceptance #6 pass leg)
///   * §4.5 frame gating boundary (Round 4 P0 revision, DoR acceptance #6 §4.5)
///       - T-4.5-a malformed hex
///       - T-4.5-b missing instructionAddress (no crash)
///       - T-4.5-c missing imageAddress
///       - T-4.5-d underflow (ip < ib)
///       - T-4.5-e mixed valid + invalid (唯一化 output check)
///       - T-4.5-f > maxFrames cap
///       - T-4.5-g zero valid frames
@Suite("CrashReporting tests (spec 015 §I + §4.5)")
struct CrashReportingTests {

    // MARK: - Fail-safe no-op (acceptance #4)

    @Test("DEBUG build: start() returns without touching SentrySDK")
    func debugBuild_start_isNoOp() {
        // Directly call `start()`. In DEBUG the compile-time `#if DEBUG`
        // branch guarantees it never reaches `SentrySDK.start`, so
        // `SentrySDK.isEnabled` stays false. The test suite is built in
        // DEBUG configuration by xcodebuild's default test action.
        CrashReporting.start()
        #expect(SentrySDK.isEnabled == false)
    }

    @Test("Release-path: empty GlitchTipDSN → fail-safe no-op, SDK not enabled")
    func releaseBranch_missingDSN_isNoOp() {
        // Use a test-only bundle whose Info.plist lacks the DSN key so the
        // Release-path helper takes the fail-safe branch. This proves the
        // deploy-time contract without needing an actual Release build.
        let emptyBundle = Bundle(for: EmptyBundleAnchor.self)
        CrashReporting._startRelease(bundle: emptyBundle)
        #expect(SentrySDK.isEnabled == false)
    }

    // Anchor class so we can grab a bundle other than `.main` — the test
    // bundle for `Bundle(for:)`. Its `GlitchTipDSN` key is absent, which is
    // exactly the "missing DSN" scenario.
    private final class EmptyBundleAnchor {}

    // MARK: - Adversarial rejection (acceptance #6, 7 categories)

    @Test("extra: non-empty bag → drop whole event")
    func sanitize_rejects_populatedExtra() {
        let event = makeCrashEvent()
        event.extra = ["heartRate": "172"]
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("context: non-empty bag → drop whole event")
    func sanitize_rejects_populatedContext() {
        let event = makeCrashEvent()
        event.context = ["custom": ["weight": "70"]]
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("breadcrumbs: non-empty → drop whole event")
    func sanitize_rejects_populatedBreadcrumbs() {
        let event = makeCrashEvent()
        let crumb = Breadcrumb()
        crumb.message = "workout started"
        event.breadcrumbs = [crumb]
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("request: non-empty → drop whole event")
    func sanitize_rejects_populatedRequest() {
        let event = makeCrashEvent()
        let req = SentryRequest()
        req.url = "https://api.example.com/health"
        event.request = req
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("tags: non-empty → drop whole event")
    func sanitize_rejects_populatedTags() {
        let event = makeCrashEvent()
        event.tags = ["userTier": "premium"]
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("user.email → drop whole event")
    func sanitize_rejects_userEmail() {
        let event = makeCrashEvent()
        let u = User()
        u.email = "u@x.com"
        event.user = u
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("user.username → drop whole event")
    func sanitize_rejects_userUsername() {
        let event = makeCrashEvent()
        let u = User()
        u.username = "leepepe"
        event.user = u
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("user.ipAddress → drop whole event")
    func sanitize_rejects_userIP() {
        let event = makeCrashEvent()
        let u = User()
        u.ipAddress = "10.0.0.1"
        event.user = u
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("user.name → drop whole event")
    func sanitize_rejects_userName() {
        let event = makeCrashEvent()
        let u = User()
        u.name = "Real Name"
        event.user = u
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("message: free-form sentence → drop whole event")
    func sanitize_rejects_freeformMessage() {
        let event = makeCrashEvent()
        event.message = SentryMessage(formatted: "Died while reading heart rate 172bpm")
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    // MARK: - §4.4 exception token gate (DiagnosticSanitizer.sanitizeTerminationReason)

    @Test("exception.value: free-form text (spaces / punctuation) → drop whole event")
    func sanitize_rejects_freeformExceptionValue() {
        let event = makeCrashEvent()
        // Replace with a valid frame + a value that fails byte allow-list.
        let ex = Exception(value: "crashed while reading heart rate", type: "SIGSEGV")
        ex.stacktrace = SentryStacktrace(frames: [defaultValidFrame()], registers: [:])
        event.exceptions = [ex]
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("exception.type: free-form text → drop whole event")
    func sanitize_rejects_freeformExceptionType() {
        let event = makeCrashEvent()
        let ex = Exception(value: "EXC_BAD_ACCESS", type: "signal from user 'lee pepe'")
        ex.stacktrace = SentryStacktrace(frames: [defaultValidFrame()], registers: [:])
        event.exceptions = [ex]
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    // MARK: - Clean crash pass (acceptance #6 pass leg)

    @Test("clean crash event: allow-listed fields cleared, addresses retained")
    func sanitize_passes_cleanEvent_scrubsAllowlist() throws {
        let event = makeCrashEvent()
        // Sanity: input has a package with a full container path.
        event.exceptions?.first?.stacktrace?.frames.first?.package =
            "/private/var/containers/Bundle/Application/.../VitalStride.app/VitalStride"

        let out = try #require(CrashReporting.sanitize(sentryEvent: event))

        // Cleared allow-list fields.
        #expect(out.extra == nil)
        #expect(out.context == nil)
        #expect(out.breadcrumbs == nil)
        #expect(out.request == nil)
        #expect(out.tags == nil)
        #expect(out.threads == nil)
        #expect(out.stacktrace == nil)
        #expect(out.user == nil)
        #expect(out.message == nil)

        // Retained addresses (dSYM keys) + basename-only package.
        let frame = try #require(out.exceptions?.first?.stacktrace?.frames.first)
        #expect(frame.instructionAddress == "0x00000001045bcabc")
        #expect(frame.imageAddress == "0x0000000104200000")
        #expect(frame.symbolAddress == "0x00000001045bca00")
        #expect(frame.function == nil)
        #expect(frame.fileName == nil)
        #expect(frame.module == nil)
        #expect(frame.lineNumber == nil)
        #expect(frame.columnNumber == nil)
        #expect(frame.package == "VitalStride")
    }

    // MARK: - debugMeta retention (acceptance #6 §4.1 保留 row)

    @Test("clean crash: non-nil debugMeta retained (dSYM symbolication keys)")
    func sanitize_retainsDebugMeta_whenPresent() throws {
        let event = makeCrashEvent()
        let dm = DebugMeta()
        dm.type = "macho"
        dm.debugID = "ABCDEF01-2345-6789-ABCD-EF0123456789"
        dm.codeFile = "VitalStride"
        dm.imageAddress = "0x0000000104200000"
        event.debugMeta = [dm]

        let out = try #require(CrashReporting.sanitize(sentryEvent: event))

        let retained = try #require(out.debugMeta)
        #expect(retained.count == 1)
        #expect(retained.first?.debugID == "ABCDEF01-2345-6789-ABCD-EF0123456789")
        #expect(retained.first?.type == "macho")
        #expect(retained.first?.codeFile == "VitalStride")
        #expect(retained.first?.imageAddress == "0x0000000104200000")
    }

    @Test("clean crash: nil debugMeta stays nil (no synthetic values injected)")
    func sanitize_leavesNilDebugMeta_asNil() throws {
        let event = makeCrashEvent()
        event.debugMeta = nil

        let out = try #require(CrashReporting.sanitize(sentryEvent: event))
        #expect(out.debugMeta == nil)
    }

    // MARK: - §4.5 boundary tests (Round 4 P0 revision)

    @Test("§4.5-a malformed hex instructionAddress → single-frame event dropped")
    func t4_5_a_malformedHex_rejects() {
        let f = makeFrame(instr: "0xZZZZ", image: "0x100")
        let event = makeCrashEvent(frames: [f])
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("§4.5-b missing instructionAddress → frame rejected, no crash")
    func t4_5_b_missingInstruction_noCrash() {
        let f = makeFrame(instr: nil, image: "0x100")
        let event = makeCrashEvent(frames: [f])
        // Must NOT trap. Result is `nil` (no accepted frames).
        var result: Event? = event  // seed to satisfy compiler
        #expect(throws: Never.self) {
            result = CrashReporting.sanitize(sentryEvent: event)
        }
        #expect(result == nil)
    }

    @Test("§4.5-c missing imageAddress → frame rejected")
    func t4_5_c_missingImage_rejects() {
        let f = makeFrame(instr: "0x100", image: nil)
        let event = makeCrashEvent(frames: [f])
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("§4.5-d underflow (ip < ib) → frame rejected")
    func t4_5_d_underflow_rejects() {
        let f = makeFrame(instr: "0x100", image: "0x200")
        let event = makeCrashEvent(frames: [f])
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    @Test("§4.5-e mixed valid + invalid: output = accepted subset only")
    func t4_5_e_mixed_producesAcceptedSubset() throws {
        // Interleaved [valid_A, invalid, valid_B, invalid, valid_C]. Wrong
        // implementations that take `originalFrames.prefix(3)` would surface
        // an invalid frame at index 1; the accepted-subset contract requires
        // frames[1] == valid_B.instructionAddress instead.
        let valid_A = makeFrame(instr: "0x00000001045bca10", image: "0x0000000104200000")
        let invalid_1 = makeFrame(instr: "0xZZZZ", image: "0x100")
        let valid_B = makeFrame(instr: "0x00000001045bca20", image: "0x0000000104200000")
        let invalid_2 = makeFrame(instr: nil, image: "0x0000000104200000")
        let valid_C = makeFrame(instr: "0x00000001045bca30", image: "0x0000000104200000")

        let event = makeCrashEvent(frames: [valid_A, invalid_1, valid_B, invalid_2, valid_C])
        let out = try #require(CrashReporting.sanitize(sentryEvent: event))

        let frames = try #require(out.exceptions?.first?.stacktrace?.frames)
        #expect(frames.count == 3)
        #expect(frames[0].instructionAddress == "0x00000001045bca10")
        #expect(frames[1].instructionAddress == "0x00000001045bca20")
        #expect(frames[2].instructionAddress == "0x00000001045bca30")
    }

    @Test("§4.5-f > maxFrames: cap to maxFrames, retain top-of-stack order")
    func t4_5_f_cap_preservesTopOrder() throws {
        // 150 valid frames — all should be accepted before the cap. Result
        // must be exactly 128 (TelemetryKit `DiagnosticSanitizer.maxFrames`).
        var frames: [Frame] = []
        for i in 0..<150 {
            let ip = 0x1045bc0000 + UInt64(i)
            let ipHex = "0x" + String(ip, radix: 16)
            frames.append(makeFrame(instr: ipHex, image: "0x0000000104200000"))
        }
        let event = makeCrashEvent(frames: frames)
        let out = try #require(CrashReporting.sanitize(sentryEvent: event))
        let outFrames = try #require(out.exceptions?.first?.stacktrace?.frames)
        #expect(outFrames.count == 128)
        // Top-of-stack retained: index 0 corresponds to input frame 0.
        #expect(outFrames.first?.instructionAddress == "0x" + String(0x1045bc0000, radix: 16))
    }

    @Test("§4.5-g zero valid frames → drop whole event")
    func t4_5_g_noValidFrames_dropsEvent() {
        // Both frames invalid; nothing makes it through mapping. T001 also
        // rejects on `guard !cleanFrames.isEmpty`.
        let event = makeCrashEvent(frames: [
            makeFrame(instr: nil, image: nil),
            makeFrame(instr: "0xZZ", image: "0xZZ"),
        ])
        #expect(CrashReporting.sanitize(sentryEvent: event) == nil)
    }

    // MARK: - Test fixtures

    /// Build a minimal crash `Event` with a single valid frame. Callers can
    /// mutate the returned event or pass their own frame list.
    private func makeCrashEvent(frames: [Frame]? = nil) -> Event {
        let event = Event(level: .fatal)
        let ex = Exception(value: "EXC_BAD_ACCESS", type: "SIGSEGV")
        let useFrames = frames ?? [defaultValidFrame()]
        ex.stacktrace = SentryStacktrace(frames: useFrames, registers: [:])
        event.exceptions = [ex]
        return event
    }

    /// One canonical valid frame: real hex `instructionAddress` /
    /// `imageAddress` / `symbolAddress`, nil `function`/`fileName`/`module`,
    /// and a `package` that starts empty (tests may overwrite it).
    private func defaultValidFrame() -> Frame {
        let f = Frame()
        f.instructionAddress = "0x00000001045bcabc"
        f.imageAddress = "0x0000000104200000"
        f.symbolAddress = "0x00000001045bca00"
        f.function = nil
        f.fileName = nil
        f.module = nil
        return f
    }

    /// Factory: raw Sentry `Frame` with the supplied hex address strings.
    private func makeFrame(instr: String?, image: String?) -> Frame {
        let f = Frame()
        f.instructionAddress = instr
        f.imageAddress = image
        return f
    }
}
