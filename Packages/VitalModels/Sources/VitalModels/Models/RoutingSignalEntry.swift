import Foundation
import SwiftData

@Model
public final class RoutingSignalEntry {
    public var kind: String = ""
    public var provider: String = ""
    public var deviceTier: String = ""
    public var latencyMs: Int = 0
    public var schemaValid: Bool = false
    public var accepted: Bool?
    public var timestamp: Date = Date()

    public init(
        kind: String,
        provider: String,
        deviceTier: String,
        latencyMs: Int,
        schemaValid: Bool,
        accepted: Bool? = nil,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.provider = provider
        self.deviceTier = deviceTier
        self.latencyMs = latencyMs
        self.schemaValid = schemaValid
        self.accepted = accepted
        self.timestamp = timestamp
    }
}
