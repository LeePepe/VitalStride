/// Pure sanitization chokepoint for third-party crash-reporting events
/// (spec 015-glitchtip-crash-reporting, T001).
///
/// This is the TelemetryKit-side, Sentry/MetricKit-free complement to
/// ``DiagnosticSanitizer``. It operates on a lightweight, dependency-free
/// intermediate representation (``RawCrashEvent``): the app's `beforeSend`
/// callback (T002) converts a Sentry `Event` → ``RawCrashEvent``, calls
/// this sanitizer, then converts the returned ``TelemetryDiagnostic`` back
/// into a scrubbed Sentry `Event` (or drops it if the sanitizer returned
/// `nil`).
///
/// Rules (Constitution §I; ADR-0012 §Decision.3 "reject the whole frame,
/// never silently truncate"):
/// * Only two shapes of payload may leave the device: a sanitized crash
///   stack (via ``DiagnosticSanitizer``) and coarse device metadata
///   (OS version, app build).
/// * Every free-form field that a third-party SDK typically populates —
///   `extra`, `contexts`, `breadcrumbs`, `request`, and the top-level
///   `message` — is on an allow-list. If any of them carries a value we
///   cannot structurally prove to be safe, the entire event is rejected
///   (return `nil`), never partially forwarded.
///
/// Kept as an `enum` namespace of `static` pure functions so it stays
/// trivially unit-testable without Sentry, MetricKit, or any device
/// runtime. The type must remain `Sendable` (all values here are value
/// types) — see TelemetryKit CONTEXT.md red-line §II.
public enum CrashEventSanitizer {
    /// Sanitize a raw crash event.
    ///
    /// Returns a ``TelemetryDiagnostic`` (safe to forward) or `nil` (the
    /// whole event must be dropped). Never returns a partially-scrubbed
    /// event: the caller cannot re-use rejected input in any form.
    ///
    /// - Parameters:
    ///   - raw: The intermediate representation the app extracted from a
    ///     third-party SDK event.
    ///   - kind: The diagnostic kind (defaults to `.crash`; `.hang` is
    ///     also legal and travels the same channel).
    public static func sanitize(
        _ raw: RawCrashEvent,
        kind: TelemetryDiagnostic.Kind = .crash
    ) -> TelemetryDiagnostic? {
        // 1. Free-form dictionaries and lists must be empty. A single
        //    populated key means the upstream SDK captured something we
        //    did not model — reject the whole event rather than guess
        //    which key was safe. This is the "整帧拒绝" discipline from
        //    ADR-0012 §Decision.3 lifted from frame-level to event-level.
        guard raw.extra.isEmpty else { return nil }
        guard raw.contexts.isEmpty else { return nil }
        guard raw.breadcrumbs.isEmpty else { return nil }
        guard raw.request.isEmpty else { return nil }
        guard raw.tags.isEmpty else { return nil }

        // 2. `message`, if present, must fit the same short-token shape as
        //    a termination reason (ASCII alphanumerics / _ / -; ≤64 chars).
        //    Anything else — a sentence, an email, a health value — is
        //    rejected. An empty/nil message is allowed (many SDKs omit it
        //    on crashes and rely on `terminationReason`).
        if let message = raw.message, !message.isEmpty {
            guard DiagnosticSanitizer.sanitizeTerminationReason(message) != nil else {
                return nil
            }
        }

        // 3. `user` may only carry an opaque anonymised id token. Any of
        //    the SDK's usual PII slots (email, username, ip, name…) must
        //    be absent; the id, if present, must fit the reason-token
        //    allow-list (hex / uuid / short slug — enforced by reusing
        //    `sanitizeTerminationReason`). This blocks
        //    `user: {"email": "u@x.com"}` at the boundary.
        if let user = raw.user {
            guard user.email == nil else { return nil }
            guard user.username == nil else { return nil }
            guard user.ipAddress == nil else { return nil }
            guard user.name == nil else { return nil }
            if let id = user.id, !id.isEmpty {
                guard DiagnosticSanitizer.sanitizeTerminationReason(id) != nil else {
                    return nil
                }
            }
        }

        // 4. Frames go through the existing frame-level chokepoint. The
        //    event must retain at least one frame after sanitization —
        //    otherwise there is nothing actionable to forward and the
        //    event is dropped whole (never let an "empty crash" ping
        //    through as a bare "user X crashed" signal).
        let cleanFrames = DiagnosticSanitizer.sanitizeFrames(raw.frames)
        guard !cleanFrames.isEmpty else { return nil }

        // 5. Coarse device metadata (osVersion, appBuild, termination
        //    reason) is normalized inside the `TelemetryDiagnostic`
        //    initializer, which idempotently re-runs `DiagnosticSanitizer`.
        //    That means an adversarial `appBuild: "5; heartRate=172"` is
        //    reduced to the `"unknown"` sentinel there, not here.
        return TelemetryDiagnostic(
            kind: kind,
            osVersion: raw.osVersion,
            appBuild: raw.appBuild,
            frames: cleanFrames,
            terminationReason: raw.terminationReason
        )
    }
}

/// Sentry/MetricKit-free intermediate representation of a crash event.
///
/// The app's `beforeSend` maps a third-party SDK `Event` into this shape
/// (and back), so TelemetryKit itself never has to import that SDK. Every
/// stored value is a value type, so the whole struct is `Sendable` by
/// default (Constitution §II).
public struct RawCrashEvent: Sendable, Equatable {
    /// SDK-level top-line message (e.g. `"SIGABRT"`). Usually nil for
    /// iOS crashes; sanitizer will reject any freeform sentence.
    public var message: String?

    /// Raw call-stack frames as produced by the SDK, one string per
    /// frame. Passed through ``DiagnosticSanitizer/sanitizeFrames(_:)``.
    public var frames: [String]

    /// OS version, e.g. `"26.5.2"`. Normalized by the `TelemetryDiagnostic`
    /// initializer.
    public var osVersion: String

    /// App build (`CFBundleVersion`), e.g. `"5"`. Normalized by the
    /// `TelemetryDiagnostic` initializer.
    public var appBuild: String

    /// Termination reason / exception code (e.g. `"EXC_BAD_ACCESS"`).
    /// Normalized by the `TelemetryDiagnostic` initializer.
    public var terminationReason: String?

    /// Sentry-style `event.extra` bag. Must be empty; a non-empty bag
    /// causes the whole event to be rejected.
    public var extra: [String: String]

    /// Sentry-style `event.contexts` (device/os/app/… sub-dictionaries).
    /// Must be empty; a non-empty bag causes rejection. Device/OS metadata
    /// travels via ``osVersion`` / ``appBuild`` instead.
    public var contexts: [String: [String: String]]

    /// Sentry-style `event.breadcrumbs`. Must be empty; breadcrumb text
    /// is inherently free-form and cannot be structurally proved safe.
    public var breadcrumbs: [String]

    /// Sentry-style `event.request` (URL, headers, body). Must be empty.
    public var request: [String: String]

    /// Sentry-style `event.tags`. Must be empty; tag values are free-form
    /// strings and cannot be structurally proved safe.
    public var tags: [String: String]

    /// Sentry-style `event.user`. All PII slots (email/username/ip/name)
    /// MUST be nil; only an opaque short id token is permitted.
    public var user: RawUser?

    public init(
        message: String? = nil,
        frames: [String] = [],
        osVersion: String = "",
        appBuild: String = "",
        terminationReason: String? = nil,
        extra: [String: String] = [:],
        contexts: [String: [String: String]] = [:],
        breadcrumbs: [String] = [],
        request: [String: String] = [:],
        tags: [String: String] = [:],
        user: RawUser? = nil
    ) {
        self.message = message
        self.frames = frames
        self.osVersion = osVersion
        self.appBuild = appBuild
        self.terminationReason = terminationReason
        self.extra = extra
        self.contexts = contexts
        self.breadcrumbs = breadcrumbs
        self.request = request
        self.tags = tags
        self.user = user
    }
}

/// Sentry-style user block, mapped into an intermediate representation
/// so TelemetryKit does not import Sentry.
public struct RawUser: Sendable, Equatable {
    public var id: String?
    public var email: String?
    public var username: String?
    public var ipAddress: String?
    public var name: String?

    public init(
        id: String? = nil,
        email: String? = nil,
        username: String? = nil,
        ipAddress: String? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.email = email
        self.username = username
        self.ipAddress = ipAddress
        self.name = name
    }
}
