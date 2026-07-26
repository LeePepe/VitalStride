import Foundation
import os
import Sentry
import TelemetryKit

/// App-side adapter that wires sentry-cocoa into the TelemetryKit
/// `CrashEventSanitizer` chokepoint defined by T001 (MY-1313, ADR-0013).
///
/// spec: `specs/015-glitchtip-crash-reporting/`
///
/// # Layer boundary
/// This file lives in the iOS `VitalStride` app target only (Mac/Watch/Widgets
/// do NOT link Sentry — Constitution §VII). It is the **only** file allowed
/// to `import Sentry`; TelemetryKit stays Sentry-free by design (T001).
///
/// # Privacy chokepoint (Constitution §I)
/// `beforeSend` runs every outgoing event through ``sanitize(sentryEvent:)``,
/// which converts the Sentry `Event` into TelemetryKit's ``RawCrashEvent``
/// intermediate, calls ``CrashEventSanitizer/sanitize(_:)``, and — only if
/// that returns non-nil AND the 1:1 frame gating holds — rebuilds a scrubbed
/// event to hand back to the SDK. Any adversarial field (breadcrumb text,
/// heart-rate in `extra`, PII in `user`, malformed frame address) causes the
/// **whole event** to be dropped (integer rejection, per T001).
///
/// # Fail-safe no-op
/// * DEBUG builds return before touching the SDK (ADR-0013 §Decision.4).
/// * Missing / empty `GlitchTipDSN` Info.plist value returns before calling
///   `SentrySDK.start(...)`. Nothing is ever transported without a DSN.
///
/// # Not a product-code capture surface
/// Product code MUST NOT invoke the SDK's manual event-capture API directly
/// (§V narrow exception: only the SDK's automatic MetricKit channel is
/// allowed). Enforced by acceptance criterion #7.
enum CrashReporting {
    private static let logger = Logger(subsystem: "com.vitalstride", category: "CrashReporting")

    /// Info.plist key populated by the `INFOPLIST_KEY_GlitchTipDSN` build
    /// setting (see `project.yml`). Value is substituted from the
    /// `$(GLITCHTIP_DSN)` build setting, which CI (MY-1316) supplies via
    /// fastlane xcargs and local Debug builds leave empty.
    static let dsnInfoPlistKey = "GlitchTipDSN"

    /// Start crash reporting. Idempotent-safe: repeated calls without a DSN
    /// stay no-ops; with a DSN the underlying SDK guards against double-start.
    ///
    /// - Parameter bundle: The bundle to read the DSN from. Defaults to
    ///   `.main`; tests inject an empty bundle to exercise the fail-safe
    ///   no-op path.
    static func start(bundle: Bundle = .main) {
        #if DEBUG
        // ADR-0013 §Decision.4: DEBUG builds do not transport. Skip start()
        // entirely so `SentrySDK.isEnabled` stays false and no `beforeSend`
        // hook can accidentally fire in developer workflows.
        _ = bundle  // keep parameter live under DEBUG (silence unused-arg)
        return
        #else
        _startRelease(bundle: bundle)
        #endif
    }

    /// Release-configuration start path, factored out so the fail-safe no-op
    /// branch is unit-testable without a Release build. Not part of the
    /// product API surface.
    internal static func _startRelease(bundle: Bundle) {
        guard let dsn = bundle.object(forInfoDictionaryKey: dsnInfoPlistKey) as? String,
              !dsn.isEmpty else {
            // fail-safe no-op: CI (MY-1316) has not yet supplied GLITCHTIP_DSN,
            // or this is a local build. Do not start the SDK, do not transport.
            logger.warning("GlitchTipDSN missing or empty — crash reporting disabled")
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.enableMetricKit = true
            options.debug = false
            options.beforeSend = { event in
                CrashReporting.sanitize(sentryEvent: event)
            }
        }
    }

    // MARK: - Sanitize chokepoint (§I; T001 adapter)

    /// The single Sentry-side adapter that converts a `SentryEvent` into
    /// TelemetryKit's ``RawCrashEvent`` intermediate, runs it through
    /// ``CrashEventSanitizer/sanitize(_:)``, and either returns a rebuilt
    /// scrubbed event (all allow-listed fields cleared, frames rewritten
    /// per §4.4) or `nil` to drop the whole event (integer rejection).
    ///
    /// Marked `internal` so unit tests can hit it directly without spinning
    /// up the SDK; product code must never call it.
    internal static func sanitize(sentryEvent event: Event) -> Event? {
        // 1. Map frames from the first exception's stacktrace. Pair each
        //    mapped IR string with its originating SentryFrame so that
        //    invalid frames are structurally impossible to resurrect on the
        //    output side (§4.5 唯一化输出规则).
        guard let exception = event.exceptions?.first else { return nil }
        guard let stacktrace = exception.stacktrace else { return nil }
        let originalFrames = stacktrace.frames
        let acceptedPairs: [AcceptedFrame] = originalFrames.compactMap(Self.mapFrame(_:))

        // 2. Cap frames at TelemetryKit's `maxFrames` — only ever from the
        //    accepted subset. Never slice the original array.
        let cappedPairs = Array(acceptedPairs.prefix(DiagnosticSanitizer.maxFrames))

        // 3. Build the intermediate representation. Every non-empty
        //    allow-listed bag (extra/breadcrumbs/request/tags) — and any
        //    *unexpected* (non-SDK) context key — makes T001 reject the whole
        //    event; that is the point. SDK-auto-attached standard contexts are
        //    excluded from the reject signal (see `unexpectedContext`); their
        //    values are dropped wholesale on the rebuild path (step 6) and
        //    never reach the wire.
        let raw = RawCrashEvent(
            message: event.message?.formatted,
            frames: cappedPairs.map(\.ir),
            osVersion: "",
            appBuild: "",
            terminationReason: exception.value,
            extra: stringifiedExtra(event.extra),
            contexts: unexpectedContext(event.context),
            breadcrumbs: breadcrumbMessages(event.breadcrumbs),
            request: stringifiedRequest(event.request),
            tags: event.tags ?? [:],
            user: mappedUser(event.user)
        )

        // 4. Chokepoint. Any policy violation → nil → drop the whole event.
        guard let sanitized = CrashEventSanitizer.sanitize(raw) else { return nil }

        // 4a. §4.4 exception-token gate: both `value` and `type` must survive
        //     `DiagnosticSanitizer.sanitizeTerminationReason` (byte allow-list
        //     + ≤64 length). Either failure → drop the whole event; the
        //     outbound exception is rebuilt from the sanitized values so any
        //     out-of-band whitespace never reaches the wire.
        guard let sanitizedValue = DiagnosticSanitizer.sanitizeTerminationReason(exception.value) else {
            return nil
        }
        guard let sanitizedType = DiagnosticSanitizer.sanitizeTerminationReason(exception.type) else {
            return nil
        }

        // 5. 1:1 gating (§4.5 唯一化输出规则): if T001 dropped any mapped
        //    frame (byte allow-list / length / offset-suffix structure), the
        //    accepted subset is no longer aligned — refuse to output a
        //    partial event.
        guard sanitized.frames.count == cappedPairs.count else { return nil }

        // 6. Rebuild the outgoing event: clear every §4.1 "clear" field,
        //    rewrite the exception's stacktrace using the accepted subset.
        event.error = nil
        event.logger = nil
        event.serverName = nil
        event.transaction = nil
        event.tags = nil
        event.extra = nil
        event.fingerprint = nil
        event.user = nil
        // Privacy anchor for the SDK-auto context whitelist: this
        // unconditional clear is why `unexpectedContext` may safely exclude
        // device/os/app from the reject signal — their nested values never
        // reach the wire. Do not remove without reintroducing a per-key strip.
        event.context = nil
        event.threads = nil
        event.stacktrace = nil
        event.breadcrumbs = nil
        event.request = nil
        event.message = nil

        // Rebuild first exception. §4.4: clear mechanism/module; use the
        // sanitized value/type tokens from step 4a (byte allow-list survivors
        // only); keep threadId.
        let cleanExc = Exception(value: sanitizedValue, type: sanitizedType)
        cleanExc.threadId = exception.threadId
        cleanExc.mechanism = nil
        cleanExc.module = nil

        // Rebuild stacktrace ONLY from `cappedPairs.map(\.frame)` — never
        // from the original array. Each retained SentryFrame is scrubbed
        // per §4.4 (function/fileName/module/lineNumber/columnNumber cleared;
        // package → basename; instruction/imageAddress/symbolAddress kept).
        let scrubbedFrames: [Frame] = cappedPairs.map { pair in
            let f = pair.frame
            f.function = nil
            f.fileName = nil
            f.module = nil
            f.lineNumber = nil
            f.columnNumber = nil
            if let pkg = f.package {
                f.package = (pkg as NSString).lastPathComponent
            }
            return f
        }
        let cleanST = SentryStacktrace(frames: scrubbedFrames, registers: [:])
        cleanExc.stacktrace = cleanST

        event.exceptions = [cleanExc]
        return event
    }

    // MARK: - §4.5 frame mapping

    /// Paired mapped-IR + originating `SentryFrame`. Invariant: the frame
    /// passed structural gating (parseable hex addresses, non-underflow
    /// offset), and its IR string is safe to hand to T001. Frames that fail
    /// gating never enter this collection.
    fileprivate struct AcceptedFrame {
        let ir: String
        let frame: Frame
    }

    /// §4.5 (Round 4 P0 revision): map a raw `SentryFrame` into an IR string,
    /// or `nil` if the frame fails any structural gate. No force-unwrap on
    /// hex parsing, no `"unknown/+0"` fallback, no under-flow.
    fileprivate static func mapFrame(_ frame: Frame) -> AcceptedFrame? {
        // instructionAddress (required, hex, parseable)
        guard let ip = parseHex(frame.instructionAddress) else { return nil }
        // imageAddress (required, hex, parseable)
        guard let ib = parseHex(frame.imageAddress) else { return nil }
        // underflow guard: negative offset = structurally invalid
        guard ip >= ib else { return nil }
        // basename: keep only the binary filename, never the full path
        let binary: String
        if let pkg = frame.package {
            binary = (pkg as NSString).lastPathComponent
        } else {
            binary = "unknown"
        }
        // Structural shape: "<binary> 0x<hex-ip> +<decimal-offset>". Uses
        // hex ip (not `frame.function`) to avoid free-form symbol names
        // passing the T001 offset-suffix check by accident.
        let ir = "\(binary) 0x\(String(ip, radix: 16)) +\(ip - ib)"
        return AcceptedFrame(ir: ir, frame: frame)
    }

    /// Parse a Sentry-style hex address string (with or without `0x` prefix)
    /// into `UInt64`. Returns nil on malformed / empty / non-hex input; never
    /// traps.
    fileprivate static func parseHex(_ raw: String?) -> UInt64? {
        guard let raw, !raw.isEmpty else { return nil }
        let stripped: String
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            stripped = String(raw.dropFirst(2))
        } else {
            stripped = raw
        }
        guard !stripped.isEmpty else { return nil }
        return UInt64(stripped, radix: 16)
    }

    // MARK: - allow-list mapping helpers (§4.1)

    /// Flatten Sentry `[String: Any]?` extra bag into `[String: String]`.
    /// Any populated key makes T001 reject the whole event; the flatten is
    /// only there so that "populated" is faithfully surfaced to the check.
    private static func stringifiedExtra(_ raw: [String: Any]?) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in raw ?? [:] {
            out[k] = String(describing: v)
        }
        return out
    }

    /// Context keys that sentry-cocoa auto-attaches to **every** event before
    /// `beforeSend` runs (device model, OS version, app build, runtime, …).
    /// These are SDK-populated metadata, not app-supplied data.
    ///
    /// These keys are **never forwarded**: the rebuild path unconditionally
    /// clears the whole context bag (`event.context = nil`, step 6) before the
    /// event leaves `sanitize`. So the *only* thing this set controls is the
    /// §I reject signal (see ``unexpectedContext(_:)``) — it is NOT an
    /// allow-list of values permitted onto the wire.
    ///
    /// Production bug (2026-07-25): the §I chokepoint rejects any event whose
    /// `contexts` bag is non-empty. Because these standard keys are *always*
    /// present on a real crash, that gate silently dropped 100% of production
    /// crashes. Excluding them from the "unexpected context" signal restores
    /// crash delivery; the privacy boundary is unchanged because (a) their
    /// nested values are still never transported (step 6 clears them), and
    /// (b) any *non-standard* (app-injected) context key still trips the
    /// whole-event reject.
    private static let sdkAutoAttachedContextKeys: Set<String> = [
        "device", "os", "app", "runtime", "culture", "gpu", "trace",
    ]

    /// Reduce Sentry's `contexts` bag to only the **unexpected** (non-SDK)
    /// entries — the ones whose mere presence must reject the whole event at
    /// the §I chokepoint. SDK-auto-attached standard contexts
    /// (see ``sdkAutoAttachedContextKeys``) are dropped here: they are not a
    /// policy violation and their values never reach the wire regardless (the
    /// rebuild path clears `event.context` wholesale in step 6).
    ///
    /// Values are stringified only so the chokepoint's "must be empty" check
    /// can observe *that* an unexpected key was populated; nothing returned
    /// here is ever transported.
    ///
    /// - Important: The privacy guarantee for the whitelisted standard
    ///   contexts rests on the unconditional `event.context = nil` in step 6.
    ///   A future refactor that removes that clear would silently reopen a
    ///   leak, so the two must stay coupled.
    private static func unexpectedContext(_ raw: [String: [String: Any]]?) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for (k, sub) in raw ?? [:] {
            if sdkAutoAttachedContextKeys.contains(k) { continue }
            var inner: [String: String] = [:]
            for (ik, iv) in sub {
                inner[ik] = String(describing: iv)
            }
            out[k] = inner
        }
        return out
    }

    /// Extract breadcrumb "message" text into a flat string list. T001's
    /// contract is that this list must be empty; any breadcrumb (even with
    /// an empty message) is captured here so an adversarial breadcrumb chain
    /// still trips the reject.
    private static func breadcrumbMessages(_ raw: [Breadcrumb]?) -> [String] {
        (raw ?? []).map { $0.message ?? "" }
    }

    /// Project `SentryRequest` into a stringy bag so T001's "must-be-empty"
    /// gate can trip on any populated field.
    private static func stringifiedRequest(_ raw: SentryRequest?) -> [String: String] {
        guard let raw else { return [:] }
        var out: [String: String] = [:]
        if let url = raw.url { out["url"] = url }
        if let method = raw.method { out["method"] = method }
        if let queryString = raw.queryString { out["queryString"] = queryString }
        if let cookies = raw.cookies { out["cookies"] = cookies }
        if let fragment = raw.fragment { out["fragment"] = fragment }
        if let bodySize = raw.bodySize { out["bodySize"] = String(describing: bodySize) }
        return out
    }

    /// Map `SentryUser` into T001's ``RawUser`` allow-list; ignore
    /// `segment`/`geo`/`data` (never map non-crash PII paths). §4.3.
    private static func mappedUser(_ raw: User?) -> RawUser? {
        guard let raw else { return nil }
        return RawUser(
            id: raw.userId,
            email: raw.email,
            username: raw.username,
            ipAddress: raw.ipAddress,
            name: raw.name
        )
    }
}
