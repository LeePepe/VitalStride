import Foundation

public struct FlightReadout: Equatable, Sendable {
    public enum Source: String, Sendable {
        case localOverride
        case remote
        case `default`
    }

    public let value: Bool
    public let source: Source
    public let remoteValue: Bool?
    public let defaultValue: Bool

    public init(value: Bool, source: Source, remoteValue: Bool?, defaultValue: Bool) {
        self.value = value
        self.source = source
        self.remoteValue = remoteValue
        self.defaultValue = defaultValue
    }
}
