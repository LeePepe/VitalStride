import Foundation
import SwiftData

@Model
public final class UserInterest {
    #Unique<UserInterest>([\.sampleType])

    public var sampleType: String = ""
    public var tapCount: Int = 0
    public var lastTappedDate: Date = Date()

    public init(
        sampleType: String,
        tapCount: Int = 1,
        lastTappedDate: Date = Date()
    ) {
        self.sampleType = sampleType
        self.tapCount = tapCount
        self.lastTappedDate = lastTappedDate
    }
}
