import Foundation
import TelemetryKit
import VitalModels

/// Helpers that convert app-domain values into locale-independent
/// `TelemetryIdentifier`s for analytics. Centralizing the mapping keeps
/// telemetry parameter values stable across UI changes and translations.
enum TelemetryHelpers {
    /// English identifier for an `AppTab`. Stable strings the analytics
    /// pipeline can group on across locales.
    static func tabIdentifier(_ tab: AppTab) -> TelemetryIdentifier {
        switch tab {
        case .overview: "overview"
        case .workout: "workout"
        case .data: "data"
        case .ai: "ai"
        case .settings: "settings"
        }
    }

    /// English identifier for a workout start source. Mapped to fixed
    /// canonical strings (`blank` / `history` / `template` / `resume`).
    static func sourceIdentifier(_ source: WorkoutStartSource) -> TelemetryIdentifier {
        switch source {
        case .blank: "blank"
        case .fromWorkout: "history"
        case .fromTemplate: "template"
        case .resume: "resume"
        }
    }

    /// Convert an `Exercise`'s canonical English name into a telemetry
    /// identifier. Falls back to `"unknown"` when the English name cannot
    /// be represented as a canonical identifier.
    ///
    /// We never pass the localized display name or `nameZh` here — that
    /// would fragment analytics across user languages.
    static func exerciseIdentifier(_ exercise: Exercise?) -> TelemetryIdentifier {
        guard let exercise else { return "unknown" }
        return identifier(forEnglishName: exercise.nameEn)
    }

    static func identifier(forEnglishName name: String) -> TelemetryIdentifier {
        let slug = Self.slugify(name)
        if let identifier = TelemetryIdentifier(validating: slug) {
            return identifier
        }
        return "unknown"
    }

    /// Lowercase ASCII slug: spaces and unsupported punctuation collapse
    /// to `_`, and any non-ASCII codepoint is dropped. The result is
    /// validated by `TelemetryIdentifier`.
    static func slugify(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var previousWasSeparator = false
        for scalar in input.unicodeScalars {
            let value = scalar.value
            let isLowerAlpha = value >= 0x61 && value <= 0x7A
            let isUpperAlpha = value >= 0x41 && value <= 0x5A
            let isDigit = value >= 0x30 && value <= 0x39
            let isHyphen = value == 0x2D
            let isDot = value == 0x2E
            if isLowerAlpha || isDigit || isHyphen || isDot {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if isUpperAlpha {
                let lower = Unicode.Scalar(value + 0x20)!
                result.unicodeScalars.append(lower)
                previousWasSeparator = false
            } else {
                if !previousWasSeparator && !result.isEmpty {
                    result.append("_")
                    previousWasSeparator = true
                }
            }
        }
        while result.hasSuffix("_") { result.removeLast() }
        return result
    }
}
