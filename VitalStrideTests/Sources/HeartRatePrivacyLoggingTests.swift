import Foundation
import Testing

/// Bar B / SC-004 (Constitution I) privacy guard for HRR paths.
///
/// Static, grep-style XCTest assertions over the source files that fetch,
/// compute, or display heart-rate recovery (HRR) data. The test scans each
/// logging call site (`logger.*`, `os_log`, `print`, `signposter.*`) and
/// fails if the argument text interpolates a heart-rate sample value —
/// either directly (e.g. `\(hrr)`, `\(sample.value)`) or via any of the
/// HRR-scope identifiers whose only content is a heart-rate reading.
///
/// The check is deterministic and offline: it reads source files from the
/// working tree via `#filePath` — no live HealthKit, no simulator state.
@Suite("HRR privacy logging (Bar B)")
struct HeartRatePrivacyLoggingTests {

    /// Files that fetch, compute, or display HRR. Any log site here must
    /// stay metadata-only (sample counts, time windows, error kinds, etc.).
    static let hrrSourceFiles: [String] = [
        "WorkoutHeartRateStats.swift",
        "WorkoutDetailView.swift",
        "HealthKitWorkoutDetailView.swift",
    ]

    /// Logging call prefixes we grep for. Each hit is inspected as one
    /// balanced-parenthesis argument list.
    static let loggingCallPatterns: [String] = [
        "logger.debug(",
        "logger.info(",
        "logger.notice(",
        "logger.warning(",
        "logger.error(",
        "logger.fault(",
        "logger.trace(",
        "logger.log(",
        "logger.critical(",
        "os_log(",
        "print(",
        "signposter.emitEvent(",
        "signposter.beginInterval(",
        "signposter.endInterval(",
    ]

    /// Identifiers that carry a heart-rate sample value or a value derived
    /// exclusively from one. Interpolating any of these into a log message
    /// would leak the sample. Match is word-boundary + case-insensitive.
    static let forbiddenValueTokens: [String] = [
        "hrr",
        "bpm",
        "heartRate",
        "heart_rate",
        "heartrate",
        "sample.value",
        "sampleValue",
        "workoutSamples",
        "postSamples",
        "postWorkoutSamples",
        "dataPoint.value",
        "dataPoints",
        "lastInWorkout",
        "averageHeartRate",
        "maxHeartRate",
        "heartRateRecovery1Min",
        "zoneDistribution",
        "closest.value",
        "pulse",
    ]

    @Test("HRR source files exist under VitalStride/Sources")
    func hrrSourceFilesResolvable() throws {
        for name in Self.hrrSourceFiles {
            let path = try #require(
                Self.findSourceFile(named: name),
                "Missing HRR-scope source file: \(name)"
            )
            #expect(
                FileManager.default.fileExists(atPath: path),
                "Resolved HRR source not readable: \(path)"
            )
        }
    }

    @Test("HRR source files do not interpolate heart-rate sample values into logs")
    func hrrLogSitesAreValueFree() throws {
        for name in Self.hrrSourceFiles {
            let path = try #require(Self.findSourceFile(named: name))
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let sites = Self.logCallSites(in: source)
            for site in sites {
                let leaks = Self.forbiddenTokens(inArgument: site.argument)
                #expect(
                    leaks.isEmpty,
                    """
                    Privacy violation (Bar B / SC-004) in \(name):
                    log call `\(site.callee)` at offset \(site.location) \
                    interpolates heart-rate sample identifier(s) \(leaks).
                    Argument: \(site.argument)
                    """
                )
            }
        }
    }

    @Test("HRR calc file has zero logging call sites — sample values must never reach a logger")
    func heartRateStatsFileHasNoLogging() throws {
        let path = try #require(Self.findSourceFile(named: "WorkoutHeartRateStats.swift"))
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let sites = Self.logCallSites(in: source)
        #expect(
            sites.isEmpty,
            """
            WorkoutHeartRateStats.swift must contain no logger/print/os_log/signposter calls.
            Found: \(sites.map(\.callee))
            """
        )
    }

    // MARK: - Source scanning

    struct LogCallSite {
        let callee: String
        let argument: String
        let location: Int
    }

    /// Returns every logging call site found in `source`, with the argument
    /// text captured via balanced-parenthesis walk starting at the opening
    /// paren of the callee. String literals inside the argument (including
    /// interpolation) are captured verbatim, so subsequent token grep runs
    /// against the literal author intent — not stripped output.
    static func logCallSites(in source: String) -> [LogCallSite] {
        var sites: [LogCallSite] = []
        let chars = Array(source)
        for pattern in loggingCallPatterns {
            var searchStart = 0
            let patternChars = Array(pattern)
            while let hitStart = firstIndex(of: patternChars, in: chars, from: searchStart) {
                if isPrefixedByIdentifierChar(chars: chars, at: hitStart) {
                    searchStart = hitStart + 1
                    continue
                }
                let openParen = hitStart + patternChars.count - 1
                guard chars.indices.contains(openParen), chars[openParen] == "(" else {
                    searchStart = hitStart + 1
                    continue
                }
                guard let closeParen = matchingParen(chars: chars, openAt: openParen) else {
                    searchStart = hitStart + 1
                    continue
                }
                let argument = String(chars[(openParen + 1)..<closeParen])
                let calleeName = pattern.replacingOccurrences(of: "(", with: "")
                sites.append(
                    LogCallSite(
                        callee: calleeName,
                        argument: argument,
                        location: hitStart
                    )
                )
                searchStart = closeParen + 1
            }
        }
        return sites
    }

    static func forbiddenTokens(inArgument argument: String) -> [String] {
        let lower = argument.lowercased()
        return forbiddenValueTokens.filter { token in
            containsIdentifier(token.lowercased(), in: lower)
        }
    }

    /// Walks the character array from `openAt` (an opening paren) and returns
    /// the index of its matching close paren, respecting Swift string and
    /// comment tokens so parens inside a string literal don't unbalance the
    /// scan. Returns nil if no match is found.
    static func matchingParen(chars: [Character], openAt: Int) -> Int? {
        var depth = 0
        var i = openAt
        var inString = false
        var stringDelimiter: Character = "\""
        var escape = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                if escape {
                    escape = false
                } else if c == "\\" {
                    escape = true
                } else if c == stringDelimiter {
                    inString = false
                }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                stringDelimiter = "\""
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return i }
            case "/":
                if i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                    continue
                }
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") {
                        i += 1
                    }
                    i += 2
                    continue
                }
            default:
                break
            }
            i += 1
        }
        return nil
    }

    static func firstIndex(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= haystack.count - needle.count else { return nil }
        var i = start
        while i <= haystack.count - needle.count {
            var match = true
            for k in 0..<needle.count where haystack[i + k] != needle[k] {
                match = false
                break
            }
            if match { return i }
            i += 1
        }
        return nil
    }

    static func isPrefixedByIdentifierChar(chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return false }
        let prev = chars[index - 1]
        return prev.isLetter || prev.isNumber || prev == "_"
    }

    /// Case-insensitive identifier-substring search. `needle` and `haystack`
    /// are both expected to already be lowercased.
    static func containsIdentifier(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: .literal, range: searchRange) {
            let beforeIsBoundary: Bool = {
                guard range.lowerBound > haystack.startIndex else { return true }
                let prev = haystack[haystack.index(before: range.lowerBound)]
                return !(prev.isLetter || prev.isNumber || prev == "_")
            }()
            let afterIsBoundary: Bool = {
                guard range.upperBound < haystack.endIndex else { return true }
                let next = haystack[range.upperBound]
                return !(next.isLetter || next.isNumber || next == "_")
            }()
            if beforeIsBoundary && afterIsBoundary {
                return true
            }
            searchRange = range.upperBound..<haystack.endIndex
        }
        return false
    }

    // MARK: - Test-time source-file resolver

    static func findSourceFile(named fileName: String) -> String? {
        let fm = FileManager.default
        let start = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let enumerator = fm.enumerator(
            at: start,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == fileName, url.pathExtension == "swift" {
                if url.path.contains("/VitalStride/Sources/") {
                    return url.path
                }
            }
        }
        return nil
    }
}
