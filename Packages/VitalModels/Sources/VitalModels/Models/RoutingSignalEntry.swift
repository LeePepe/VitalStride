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

    // TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
    public var rawPromptDebug: String?
    // TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
    public var rawResponseDebug: String?

    public init(
        kind: String,
        provider: String,
        deviceTier: String,
        latencyMs: Int,
        schemaValid: Bool,
        accepted: Bool? = nil,
        timestamp: Date = Date(),
        rawPromptDebug: String? = nil,
        rawResponseDebug: String? = nil
    ) {
        self.kind = kind
        self.provider = provider
        self.deviceTier = deviceTier
        self.latencyMs = latencyMs
        self.schemaValid = schemaValid
        self.accepted = accepted
        self.timestamp = timestamp
        self.rawPromptDebug = rawPromptDebug
        self.rawResponseDebug = rawResponseDebug
    }
}
