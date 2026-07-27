import Foundation
import Testing
@testable import TelemetryKit

/// ADR-0015 §perf (阶段 4). `MetricPayloadParser` turns a MetricKit
/// `MXMetricPayload.jsonRepresentation()` blob into typed performance
/// `TelemetryEvent`s. MetricKit's `MXMetricPayload` only exists on device, so —
/// mirroring `DiagnosticBuilder` for the diagnostics path — all parsing,
/// unit-conversion and histogram-aggregation lives here in the package and is
/// exercised with hand-written JSON fixtures that copy Apple's real schema:
/// values are **unit-suffixed strings with thousands separators** (`"200,000 kB"`,
/// `"100 sec"`, `"1,000 ms"`), and launch/hang arrive as histogram buckets.
@Suite("MetricPayloadParser")
struct MetricPayloadParserTests {

    /// Small helper: run the parser over an inline JSON string.
    private func events(_ json: String) -> [TelemetryEvent] {
        MetricPayloadParser.events(fromPayloadJSON: Data(json.utf8))
    }

    /// Convenience: the single event of a given name, if present.
    private func event(named name: String, in events: [TelemetryEvent]) -> TelemetryEvent? {
        events.first { $0.eventName == name }
    }

    // MARK: - Memory (peakMemoryUsage: kB → MB)

    @Test("peak memory: '200,000 kB' → 200 MB")
    func peakMemory() {
        let json = """
        { "memoryMetrics": { "peakMemoryUsage": "200,000 kB" } }
        """
        let e = event(named: "app_memory_peak_measured", in: events(json))
        #expect(e == .appMemoryPeakMeasured(peakMemoryMB: 200))
    }

    // MARK: - CPU (cumulativeCPUTime: sec → ms)

    @Test("cpu time: '100 sec' → 100000 ms")
    func cpuTime() {
        let json = """
        { "cpuMetrics": { "cumulativeCPUTime": "100 sec" } }
        """
        let e = event(named: "app_cpu_time_measured", in: events(json))
        #expect(e == .appCPUTimeMeasured(cpuMillis: 100_000))
    }

    // MARK: - Launch (histogram → weighted average, ms)

    @Test("launch time: single bucket → bucket midpoint, ms")
    func launchSingleBucket() {
        // One bucket [1,000 ms, 1,010 ms) → midpoint 1005 ms.
        let json = """
        {
          "applicationLaunchMetrics": {
            "histogrammedTimeToFirstDraw": {
              "histogramNumBuckets": 1,
              "histogramValue": {
                "0": { "bucketCount": 50, "bucketStart": "1,000 ms", "bucketEnd": "1,010 ms" }
              }
            }
          }
        }
        """
        let e = event(named: "app_launch_time_measured", in: events(json))
        #expect(e == .appLaunchTimeMeasured(millisToFirstDraw: 1005))
    }

    @Test("launch time: multi-bucket → count-weighted average of midpoints")
    func launchWeightedAverage() {
        // bucket A mid=105 count=1, bucket B mid=205 count=3
        // weighted avg = (105*1 + 205*3) / 4 = (105 + 615)/4 = 720/4 = 180
        let json = """
        {
          "applicationLaunchMetrics": {
            "histogrammedTimeToFirstDraw": {
              "histogramValue": {
                "0": { "bucketCount": 1, "bucketStart": "100 ms", "bucketEnd": "110 ms" },
                "1": { "bucketCount": 3, "bucketStart": "200 ms", "bucketEnd": "210 ms" }
              }
            }
          }
        }
        """
        let e = event(named: "app_launch_time_measured", in: events(json))
        #expect(e == .appLaunchTimeMeasured(millisToFirstDraw: 180))
    }

    @Test("launch time: tolerates the '...Key' key-name drift across OS versions")
    func launchKeyNameDrift() {
        let json = """
        {
          "applicationLaunchMetrics": {
            "histogrammedTimeToFirstDrawKey": {
              "histogramValue": {
                "0": { "bucketCount": 2, "bucketStart": "1,000 ms", "bucketEnd": "1,010 ms" }
              }
            }
          }
        }
        """
        let e = event(named: "app_launch_time_measured", in: events(json))
        #expect(e == .appLaunchTimeMeasured(millisToFirstDraw: 1005))
    }

    @Test("launch time: empty histogram → no event")
    func launchEmptyHistogram() {
        let json = """
        {
          "applicationLaunchMetrics": {
            "histogrammedTimeToFirstDraw": { "histogramValue": {} }
          }
        }
        """
        #expect(event(named: "app_launch_time_measured", in: events(json)) == nil)
    }

    // MARK: - Hang (histogram total → normalized per foreground-hour)

    @Test("hang time: total hang normalized to per foreground-hour")
    func hangPerHour() {
        // Hang buckets: [0,100) mid=50 count=2 → 100 ms ; [100,200) mid=150 count=1 → 150 ms
        // total hang = 250 ms. Foreground = 1800 sec (0.5 h).
        // per-hour = 250 * 3600 / 1800 = 500 ms/h
        let json = """
        {
          "applicationResponsivenessMetrics": {
            "histogrammedApplicationHangTime": {
              "histogramValue": {
                "0": { "bucketCount": 2, "bucketStart": "0 ms", "bucketEnd": "100 ms" },
                "1": { "bucketCount": 1, "bucketStart": "100 ms", "bucketEnd": "200 ms" }
              }
            }
          },
          "applicationTimeMetrics": { "cumulativeForegroundTime": "1800 sec" }
        }
        """
        let e = event(named: "app_hang_time_measured", in: events(json))
        #expect(e == .appHangTimeMeasured(hangMillisPerHour: 500))
    }

    @Test("hang time: tolerates the 'histogrammedAppHangTime' key variant")
    func hangKeyVariant() {
        // total hang = 50 ms over 3600 sec (1h) → 50 ms/h
        let json = """
        {
          "applicationResponsivenessMetrics": {
            "histogrammedAppHangTime": {
              "histogramValue": {
                "0": { "bucketCount": 1, "bucketStart": "0 ms", "bucketEnd": "100 ms" }
              }
            }
          },
          "applicationTimeMetrics": { "cumulativeForegroundTime": "3600 sec" }
        }
        """
        let e = event(named: "app_hang_time_measured", in: events(json))
        #expect(e == .appHangTimeMeasured(hangMillisPerHour: 50))
    }

    @Test("hang time: missing foreground time → no event (no divide-by-zero)")
    func hangMissingForeground() {
        let json = """
        {
          "applicationResponsivenessMetrics": {
            "histogrammedApplicationHangTime": {
              "histogramValue": {
                "0": { "bucketCount": 1, "bucketStart": "0 ms", "bucketEnd": "100 ms" }
              }
            }
          }
        }
        """
        #expect(event(named: "app_hang_time_measured", in: events(json)) == nil)
    }

    @Test("hang time: zero foreground time → no event (no divide-by-zero)")
    func hangZeroForeground() {
        let json = """
        {
          "applicationResponsivenessMetrics": {
            "histogrammedApplicationHangTime": {
              "histogramValue": {
                "0": { "bucketCount": 1, "bucketStart": "0 ms", "bucketEnd": "100 ms" }
              }
            }
          },
          "applicationTimeMetrics": { "cumulativeForegroundTime": "0 sec" }
        }
        """
        #expect(event(named: "app_hang_time_measured", in: events(json)) == nil)
    }

    // MARK: - Combined payload

    @Test("full payload emits all four events")
    func fullPayload() {
        let json = """
        {
          "applicationLaunchMetrics": {
            "histogrammedTimeToFirstDraw": {
              "histogramValue": {
                "0": { "bucketCount": 1, "bucketStart": "1,000 ms", "bucketEnd": "1,010 ms" }
              }
            }
          },
          "applicationResponsivenessMetrics": {
            "histogrammedApplicationHangTime": {
              "histogramValue": {
                "0": { "bucketCount": 1, "bucketStart": "0 ms", "bucketEnd": "100 ms" }
              }
            }
          },
          "applicationTimeMetrics": { "cumulativeForegroundTime": "3600 sec" },
          "memoryMetrics": { "peakMemoryUsage": "150,000 kB" },
          "cpuMetrics": { "cumulativeCPUTime": "42 sec" }
        }
        """
        let all = events(json)
        #expect(all.contains(.appLaunchTimeMeasured(millisToFirstDraw: 1005)))
        #expect(all.contains(.appHangTimeMeasured(hangMillisPerHour: 50)))
        #expect(all.contains(.appMemoryPeakMeasured(peakMemoryMB: 150)))
        #expect(all.contains(.appCPUTimeMeasured(cpuMillis: 42_000)))
        #expect(all.count == 4)
    }

    // MARK: - Robustness

    @Test("unit mismatch is not guessed — metric skipped, others survive")
    func unitMismatchSkipsOnlyThatMetric() {
        // memory value carries the wrong unit ("MB" not "kB") → skip memory,
        // but cpu still parses.
        let json = """
        {
          "memoryMetrics": { "peakMemoryUsage": "200 MB" },
          "cpuMetrics": { "cumulativeCPUTime": "5 sec" }
        }
        """
        let all = events(json)
        #expect(event(named: "app_memory_peak_measured", in: all) == nil)
        #expect(all.contains(.appCPUTimeMeasured(cpuMillis: 5_000)))
    }

    @Test("empty payload → no events")
    func emptyPayload() {
        #expect(events("{}").isEmpty)
    }

    @Test("malformed JSON → no events, no crash")
    func malformedJSON() {
        #expect(events("not json at all {[").isEmpty)
        #expect(events("").isEmpty)
    }

    @Test("negative measurement is defensively skipped")
    func negativeSkipped() {
        let json = """
        { "cpuMetrics": { "cumulativeCPUTime": "-5 sec" } }
        """
        #expect(event(named: "app_cpu_time_measured", in: events(json)) == nil)
    }
}
