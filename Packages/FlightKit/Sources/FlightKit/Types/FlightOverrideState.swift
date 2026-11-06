import Foundation

public enum FlightOverrideState: String, CaseIterable, Codable, Hashable, Sendable {
    case useDefault
    case forceOn
    case forceOff

    public var value: Bool? {
        switch self {
        case .useDefault: nil
        case .forceOn: true
        case .forceOff: false
        }
    }

    public var displayName: String {
        switch self {
        case .useDefault: String(localized: "Default", comment: "Use the feature flag default or remote value")
        case .forceOn: String(localized: "On", comment: "Force a feature flag on")
        case .forceOff: String(localized: "Off", comment: "Force a feature flag off")
        }
    }
}

