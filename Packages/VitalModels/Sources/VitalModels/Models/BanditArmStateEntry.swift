import Foundation
import SwiftData

@Model
public final class BanditArmStateEntry {
    public var kind: String = ""
    public var deviceTier: String = ""
    public var provider: String = ""
    public var count: Int = 0
    public var rewardSum: Double = 0
    public var updatedAt: Date = Date()

    public init(
        kind: String,
        deviceTier: String,
        provider: String,
        count: Int = 0,
        rewardSum: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.kind = kind
        self.deviceTier = deviceTier
        self.provider = provider
        self.count = count
        self.rewardSum = rewardSum
        self.updatedAt = updatedAt
    }
}
