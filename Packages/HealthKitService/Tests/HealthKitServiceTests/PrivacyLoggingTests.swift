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

    /// Error-detail tokens that must never appear in aggregate health logs.
    /// We allow aggregate metadata (count, ms, status, firstSync, type) but
    /// forbid free-form error text or record-detail interpolation.
    private static let bannedErrorDetailTokens: [String] = [
        "error.localizedDescription",
        "localizedDescription",
        "errorDescription",
        "detail=",
        "record_detail",
        "recordDetail",
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

    @Test("multiline logger invocations are checked end-to-end")
    func multilineLoggerInvocationsAreChecked() {
        let safeMessage = """
        logger.info(
            "healthkit_workout_fetch_duration_ms type=workout count=42 ms=1000 firstSync=false status=ok"
        )
        """
        let unsafeMessage = """
        logger.error(
            "query type=workout count=42 ms=1000 firstSync=false status=ok" +
            " error.localizedDescription"
        )
        """

        #expect(Self.findBannedTokens(in: safeMessage).isEmpty)
        #expect(!Self.findBannedTokens(in: unsafeMessage).isEmpty)
    }

    // MARK: - Helpers

    private static func findBannedTokens(in text: String) -> [(line: Int, token: String, text: String)] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var findings: [(line: Int, token: String, text: String)] = []
        var lineIndex = 0

        while lineIndex < lines.count {
            let rawLine = String(lines[lineIndex])
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("///") {
                lineIndex += 1
                continue
            }

            guard Self.logCallSitePatterns.contains(where: { rawLine.contains($0) }) else {
                lineIndex += 1
                continue
            }

            var invocationLines = [rawLine]
            var openParentheses = rawLine.filter { $0 == "(" }.count - rawLine.filter { $0 == ")" }.count
            var endIndex = lineIndex

            while openParentheses > 0 && endIndex + 1 < lines.count {
                endIndex += 1
                let nextLine = String(lines[endIndex])
                invocationLines.append(nextLine)
                openParentheses += nextLine.filter { $0 == "(" }.count - nextLine.filter { $0 == ")" }.count
            }

            let invocation = invocationLines.joined(separator: "\n")
            let tokens = Self.bannedValueTokens + Self.bannedErrorDetailTokens
            for token in tokens where invocation.contains(token) {
                findings.append((line: lineIndex + 1, token: token, text: invocation))
            }
            lineIndex = endIndex + 1
        }

        return findings
    }

    private func assertSourceHasNoBannedLogging(at path: String) throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let findings = Self.findBannedTokens(in: source)
        for finding in findings {
            Issue.record("""
            Privacy red line violated at \(path):\(finding.line):
            Log call contains banned token '\(finding.token)'.
            Invocation:\n\(finding.text)
            """)
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
