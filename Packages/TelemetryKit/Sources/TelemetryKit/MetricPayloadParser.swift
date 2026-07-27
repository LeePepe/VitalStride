import Foundation

/// Pure parsing of MetricKit `MXMetricPayload` JSON into typed performance
/// ``TelemetryEvent``s (ADR-0015 §perf / 阶段 4).
///
/// MetricKit's `MXMetricPayload` type only exists on device and is unavailable
/// to this cross-platform package, so — mirroring ``DiagnosticBuilder`` for the
/// diagnostics path — the app-side collector hands the raw
/// `payload.jsonRepresentation()` blob here, keeping all fragile
/// unit-conversion + histogram-aggregation logic unit-testable without
/// MetricKit.
///
/// **Schema caveats** (verified against Apple's `jsonRepresentation()` output):
/// measurement values are unit-suffixed strings with thousands separators
/// (`"200,000 kB"`, `"100 sec"`, `"1,000 ms"`), launch/hang arrive as histogram
/// buckets, and some key names drift across OS versions
/// (`histogrammedTimeToFirstDraw` vs `histogrammedTimeToFirstDrawKey`), so key
/// lookups tolerate a small candidate list.
///
/// Every emitted value is an `Int` (ms / MB) — no PII, no health values — so
/// Constitution §I holds by construction. A metric that fails to parse is
/// skipped individually; the others still emit. Malformed top-level JSON yields
/// an empty array.
public enum MetricPayloadParser {

    /// Parse one MetricKit payload blob into zero or more perf events.
    public static func events(fromPayloadJSON data: Data) -> [TelemetryEvent] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        var events: [TelemetryEvent] = []
        if let e = launchEvent(from: root) { events.append(e) }
        if let e = hangEvent(from: root) { events.append(e) }
        if let e = memoryEvent(from: root) { events.append(e) }
        if let e = cpuEvent(from: root) { events.append(e) }
        return events
    }

    // MARK: - Per-metric mapping

    /// `applicationLaunchMetrics.histogrammedTimeToFirstDraw` → count-weighted
    /// average of bucket midpoints (ms).
    private static func launchEvent(from root: [String: Any]) -> TelemetryEvent? {
        guard
            let launch = root["applicationLaunchMetrics"] as? [String: Any],
            let histogram = firstNode(
                in: launch,
                keys: ["histogrammedTimeToFirstDraw", "histogrammedTimeToFirstDrawKey"]
            ),
            let averageMs = histogramWeightedAverage(histogram, unit: "ms"),
            let value = intValue(averageMs)
        else {
            return nil
        }
        return .appLaunchTimeMeasured(millisToFirstDraw: value)
    }

    /// `applicationResponsivenessMetrics.histogrammedApplicationHangTime` →
    /// total hang ms, normalized to per foreground-hour using
    /// `applicationTimeMetrics.cumulativeForegroundTime`. Skipped when
    /// foreground time is missing or non-positive (avoids divide-by-zero).
    private static func hangEvent(from root: [String: Any]) -> TelemetryEvent? {
        guard
            let responsiveness = root["applicationResponsivenessMetrics"] as? [String: Any],
            let histogram = firstNode(
                in: responsiveness,
                keys: ["histogrammedApplicationHangTime", "histogrammedAppHangTime"]
            ),
            let totalHangMs = histogramWeightedTotal(histogram, unit: "ms"),
            let timeMetrics = root["applicationTimeMetrics"] as? [String: Any],
            let foregroundSec = (timeMetrics["cumulativeForegroundTime"] as? String)
                .flatMap({ parseMeasurement($0, unit: "sec") }),
            foregroundSec > 0
        else {
            return nil
        }
        let perHour = totalHangMs * 3600.0 / foregroundSec
        guard let value = intValue(perHour) else { return nil }
        return .appHangTimeMeasured(hangMillisPerHour: value)
    }

    /// `memoryMetrics.peakMemoryUsage` (kB) → MB.
    private static func memoryEvent(from root: [String: Any]) -> TelemetryEvent? {
        guard
            let memory = root["memoryMetrics"] as? [String: Any],
            let raw = memory["peakMemoryUsage"] as? String,
            let kB = parseMeasurement(raw, unit: "kB"),
            let value = intValue(kB / 1000.0)
        else {
            return nil
        }
        return .appMemoryPeakMeasured(peakMemoryMB: value)
    }

    /// `cpuMetrics.cumulativeCPUTime` (sec) → ms.
    private static func cpuEvent(from root: [String: Any]) -> TelemetryEvent? {
        guard
            let cpu = root["cpuMetrics"] as? [String: Any],
            let raw = cpu["cumulativeCPUTime"] as? String,
            let sec = parseMeasurement(raw, unit: "sec"),
            let value = intValue(sec * 1000.0)
        else {
            return nil
        }
        return .appCPUTimeMeasured(cpuMillis: value)
    }

    // MARK: - Histogram aggregation

    /// Sum of `midpoint × bucketCount` across all buckets, in the histogram's
    /// unit. `nil` when the histogram is empty or unparseable.
    private static func histogramWeightedTotal(
        _ node: [String: Any],
        unit: String
    ) -> Double? {
        guard let buckets = node["histogramValue"] as? [String: Any], !buckets.isEmpty else {
            return nil
        }
        var total = 0.0
        var counted = 0
        for (_, raw) in buckets {
            guard
                let bucket = raw as? [String: Any],
                let start = (bucket["bucketStart"] as? String).flatMap({ parseMeasurement($0, unit: unit) }),
                let end = (bucket["bucketEnd"] as? String).flatMap({ parseMeasurement($0, unit: unit) }),
                let count = bucketCount(bucket["bucketCount"])
            else {
                continue
            }
            total += ((start + end) / 2.0) * Double(count)
            counted += 1
        }
        return counted > 0 ? total : nil
    }

    /// Count-weighted average of bucket midpoints: `Σ(mid×count) / Σcount`.
    private static func histogramWeightedAverage(
        _ node: [String: Any],
        unit: String
    ) -> Double? {
        guard let buckets = node["histogramValue"] as? [String: Any], !buckets.isEmpty else {
            return nil
        }
        var weighted = 0.0
        var totalCount = 0
        for (_, raw) in buckets {
            guard
                let bucket = raw as? [String: Any],
                let start = (bucket["bucketStart"] as? String).flatMap({ parseMeasurement($0, unit: unit) }),
                let end = (bucket["bucketEnd"] as? String).flatMap({ parseMeasurement($0, unit: unit) }),
                let count = bucketCount(bucket["bucketCount"])
            else {
                continue
            }
            weighted += ((start + end) / 2.0) * Double(count)
            totalCount += count
        }
        return totalCount > 0 ? weighted / Double(totalCount) : nil
    }

    // MARK: - Primitives

    /// Parse a unit-suffixed measurement string (`"1,000 ms"`, `"200,000 kB"`,
    /// `"100 sec"`) into its numeric value. Returns `nil` when the trailing unit
    /// does not match `expected` — the unit is never guessed.
    static func parseMeasurement(_ raw: String, unit expected: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Split off the last whitespace-separated token as the unit.
        guard let spaceIndex = trimmed.lastIndex(of: " ") else { return nil }
        let unit = trimmed[trimmed.index(after: spaceIndex)...].trimmingCharacters(in: .whitespaces)
        guard unit == expected else { return nil }
        let numberPart = trimmed[..<spaceIndex]
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(numberPart)
    }

    /// `bucketCount` may decode as `Int`, `Double`, or `NSNumber`.
    private static func bucketCount(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return nil
    }

    /// Round a non-negative, finite `Double` to `Int`. Rejects NaN / infinite /
    /// negative values (defensive — perf measurements are never negative), and
    /// values outside `Int`'s range: `Int(exactly:)` returns `nil` instead of
    /// trapping, so an out-of-range MetricKit value (e.g. `"1e20 sec"`) skips
    /// the metric rather than crashing.
    private static func intValue(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0 else { return nil }
        return Int(exactly: value.rounded())
    }

    /// First present, dictionary-typed value among a list of candidate keys.
    private static func firstNode(in dict: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let node = dict[key] as? [String: Any] { return node }
        }
        return nil
    }
}
