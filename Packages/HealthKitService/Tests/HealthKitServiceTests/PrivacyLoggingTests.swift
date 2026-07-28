import Testing
import Foundation

/// Enforces constitution §I privacy red line for the HealthKitService layer:
/// health numeric values (heart-rate bpm, kcal, distance meters, avg HR)
/// must never be interpolated into log/print statements.
///
/// This is a *source-level* grep rather than a runtime assertion because the
/// red line applies to what's *possible* to log, not just what a given call
/// path happens to do. Introduced in MY-1358 alongside `averageHeartRate` to
/// stop that value from leaking into diagnostics.
@Suite("PrivacyLogging — HealthKitService source-level red lines")
struct PrivacyLoggingTests {

    /// Words that MUST NOT appear inside `os_log` / `logger.` / `print` string
    /// interpolations in HealthKitService. Sample type identifiers, counts,
    /// and durations are fine — actual physiological values are not.
    private static let bannedValueTokens: [String] = [
        "averageHeartRate",
        "avgHR",
        "totalEnergyBurned",
        "totalDistance",
        "heartRate.value",
    ]

    /// Log-emitting patterns we scan. Matches os_log, `logger.info`,
    /// `logger.error`, `logger.debug`, and top-level `print(`.
    private static let logCallSitePatterns: [String] = [
        "logger.info(",
        "logger.error(",
        "logger.debug(",
        "logger.notice(",
        "logger.warning(",
        "os_log(",
        "print(",
    ]

    @Test("HealthKitService.swift does not log raw health numeric values")
    func healthKitServiceSourceIsClean() throws {
        let sourcePath = Self.sourceFile("HealthKitService.swift")
        try assertSourceHasNoBannedLogging(at: sourcePath)
    }

    @Test("HealthWorkoutRecord.swift does not log raw health numeric values")
    func healthWorkoutRecordSourceIsClean() throws {
        let sourcePath = Self.sourceFile("HealthWorkoutRecord.swift")
        try assertSourceHasNoBannedLogging(at: sourcePath)
    }

    // MARK: - Helpers

    private func assertSourceHasNoBannedLogging(at path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            // Skip comment lines.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("///") {
                continue
            }
            let isLogCall = Self.logCallSitePatterns.contains(where: { line.contains($0) })
            guard isLogCall else { continue }
            for banned in Self.bannedValueTokens where line.contains(banned) {
                Issue.record("""
                Privacy red line violated at \(path):\(index + 1):
                Log call contains banned value token '\(banned)'.
                Line: \(line)
                """)
            }
        }
    }

    /// Resolve `<file>` inside the HealthKitService Sources directory relative
    /// to this test file (`#filePath` points at this .swift file).
    private static func sourceFile(_ name: String, file: StaticString = #filePath) -> String {
        // #filePath = .../Packages/HealthKitService/Tests/HealthKitServiceTests/PrivacyLoggingTests.swift
        // We want    .../Packages/HealthKitService/Sources/HealthKitService/<name>
        let testFile = URL(fileURLWithPath: String(describing: file))
        let packageRoot = testFile
            .deletingLastPathComponent()   // HealthKitServiceTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // HealthKitService (package)
        return packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("HealthKitService", isDirectory: true)
            .appendingPathComponent(name)
            .path
    }
}
