import Foundation

// MARK: - AITaskKind

/// Identity of an AI-facing feature. Callers declare only the kind; `AIRouter` maps it
/// to `TaskRequirements` and picks a provider per `(kind, DeviceTier)`.
///
/// Adding a new kind: append a case here, add its entry to `AIRouter.defaultPolicy`,
/// and migrate its call site to `aiRouter.execute(.<kind>, ...)`.
public enum AITaskKind: String, Sendable, CaseIterable, Codable {
    case chat
    case overviewInsights
    case trainingAdvice
    case dataTrend
    case substitute
}

// MARK: - LatencyClass / QualityClass

/// Whether the caller is waiting on the response (interactive UI) or the work can be
/// pushed to a background priority.
public enum LatencyClass: String, Sendable, CaseIterable, Codable {
    case interactive
    case background
}

/// Coarse quality target for the response. `low` = short factual replacement suggestions;
/// `medium` = general summaries; `high` = long-form advice / structured multi-field JSON.
public enum QualityClass: String, Sendable, CaseIterable, Codable, Comparable {
    case low
    case medium
    case high

    /// Ordering used by `AIRouter` capability matching:
    /// `low < medium < high`. A provider whose `maxQuality` is at least the
    /// requirement's `quality` is eligible.
    public static func < (lhs: QualityClass, rhs: QualityClass) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}

// MARK: - TaskRequirements

/// The router's picture of what a task needs. The central policy table maps
/// `AITaskKind` → `TaskRequirements`; the router matches these against provider
/// capabilities to pick an ordering per request.
public struct TaskRequirements: Sendable, Equatable, Codable {
    public let latency: LatencyClass
    public let quality: QualityClass
    public let structured: Bool
    public let carriesHealthData: Bool

    public init(
        latency: LatencyClass,
        quality: QualityClass,
        structured: Bool,
        carriesHealthData: Bool
    ) {
        self.latency = latency
        self.quality = quality
        self.structured = structured
        self.carriesHealthData = carriesHealthData
    }
}

// MARK: - DeviceTier

/// Coarse capability tier of the current device. Controls whether the on-device
/// Apple Intelligence arm is eligible at all. `cloudOnly` devices MUST never see
/// an on-device attempt (spec FR-005).
public enum DeviceTier: String, Sendable, CaseIterable, Codable {
    case appleIntelligenceCapable
    case cloudOnly

    /// Detect the current tier via `AppleIntelligenceProvider.isAvailable`.
    ///
    /// Detection is done at call time, not cached — capability may change if the OS
    /// disables Apple Intelligence (e.g. low-power mode). The spec's "device tier
    /// changes mid-session" edge case is handled: whatever tier is observed at the
    /// point of `execute` decides the routing.
    public static func detect() -> DeviceTier {
        AppleIntelligenceProvider.isAvailable ? .appleIntelligenceCapable : .cloudOnly
    }
}
