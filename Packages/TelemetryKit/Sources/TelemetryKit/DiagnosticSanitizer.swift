/// Pure sanitization chokepoint for MetricKit diagnostics (ADR-0012 §Decision.3).
///
/// Every field that reaches ``TelemetryDiagnostic`` — and thus the third-party
/// transport — passes through here first. The rules keep only what is needed to
/// symbolicate a stack against our own dSYM (frame symbol + binary offset) and
/// drop everything else. This upholds Constitution §I structurally: a call
/// stack is symbol/address data, never app or HealthKit data, and anything that
/// does not match the allow-list shape is discarded rather than forwarded.
///
/// Kept free-function / `enum`-namespaced and dependency-free so it is unit
/// testable without MetricKit or a rendered app (MetricKit types only exist on
/// device; the sanitizer operates on already-extracted primitive values).
public enum DiagnosticSanitizer {
    /// Max frames retained. Deep stacks are truncated so a runaway recursion
    /// cannot bloat a transported payload. The crashing frames are at the top,
    /// so truncation keeps the actionable part.
    public static let maxFrames = 128

    /// Max characters per sanitized frame line. Guards against a pathological
    /// symbol name; well beyond any real mangled Swift symbol.
    public static let maxFrameLength = 512

    /// Sanitize a single raw frame description into the canonical
    /// `"<binary> <symbol> +<offset>"` shape, or `nil` if it cannot be reduced
    /// to a safe, meaningful frame.
    ///
    /// Allowed characters after sanitization: ASCII alphanumerics and a small
    /// punctuation set used by demangled Swift/C symbols and offsets
    /// (`_ . - + < > ( ) : $ # space`). Any other byte (control chars, quotes,
    /// non-ASCII — the shapes free-form user text or health strings would take)
    /// causes the whole frame to be rejected, not silently stripped, so a
    /// partially-suspicious frame never leaks a fragment.
    public static func sanitizeFrame(_ raw: String) -> String? {
        let trimmed = trim(raw)
        guard !trimmed.isEmpty, trimmed.count <= maxFrameLength else { return nil }
        guard trimmed.utf8.allSatisfy(isAllowedFrameByte) else { return nil }
        return trimmed
    }

    /// Sanitize a raw list of frames: reject non-conforming frames, cap the
    /// count. Returns the retained frames in original (top-of-stack-first)
    /// order.
    public static func sanitizeFrames(_ raw: [String]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(min(raw.count, maxFrames))
        for frame in raw {
            guard out.count < maxFrames else { break }
            if let clean = sanitizeFrame(frame) {
                out.append(clean)
            }
        }
        return out
    }

    /// Sanitize a version-like metadata string (OS version, app build) to a
    /// canonical dotted/numeric token, or a fixed `"unknown"` sentinel. Only
    /// digits, dots, and hyphens survive — never free-form text.
    public static func sanitizeVersion(_ raw: String) -> String {
        let trimmed = trim(raw)
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return "unknown" }
        let allowed = trimmed.utf8.allSatisfy(isAllowedVersionByte)
        return allowed ? trimmed : "unknown"
    }

    /// Sanitize an exception/termination token (e.g. `EXC_BAD_ACCESS`,
    /// `SIGABRT`) to canonical uppercase-ish identifier form, or `nil`.
    public static func sanitizeTerminationReason(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = trim(raw)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        let allowed = trimmed.utf8.allSatisfy(isAllowedReasonByte)
        return allowed ? trimmed : nil
    }

    // MARK: - Byte allow-lists

    private static func isAllowedVersionByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39,  // 0-9
             0x2E,         // .
             0x2D:         // -
            return true
        default:
            return false
        }
    }

    private static func isAllowedReasonByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39,  // 0-9
             0x41...0x5A,  // A-Z
             0x61...0x7A,  // a-z
             0x5F,         // _
             0x2D:         // -
            return true
        default:
            return false
        }
    }

    /// Trim leading/trailing ASCII whitespace without importing Foundation, so
    /// this sanitizer stays dependency-free and portable to any platform the
    /// package builds on.
    private static func trim(_ s: String) -> String {
        let bytes = Array(s.unicodeScalars)
        var start = 0
        var end = bytes.count
        while start < end, isWhitespace(bytes[start]) { start += 1 }
        while end > start, isWhitespace(bytes[end - 1]) { end -= 1 }
        return String(String.UnicodeScalarView(bytes[start..<end]))
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C:
            return true
        default:
            return false
        }
    }

    private static func isAllowedFrameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39,  // 0-9
             0x41...0x5A,  // A-Z
             0x61...0x7A:  // a-z
            return true
        case 0x5F,  // _
             0x2E,  // .
             0x2D,  // -
             0x2B,  // +
             0x3C,  // <
             0x3E,  // >
             0x28,  // (
             0x29,  // )
             0x3A,  // :
             0x24,  // $
             0x23,  // #  (Swift closure/thunk frames: "closure #1 in ...")
             0x20:  // space
            return true
        default:
            return false
        }
    }
}
