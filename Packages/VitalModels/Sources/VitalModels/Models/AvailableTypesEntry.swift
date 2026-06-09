import Foundation
import SwiftData

@Model
public final class AvailableTypesEntry {
    public var availableTypeRawValues: [String] = []
    public var fetchedAt: Date = Date()

    public init(
        availableTypeRawValues: [String],
        fetchedAt: Date = Date()
    ) {
        self.availableTypeRawValues = availableTypeRawValues
        self.fetchedAt = fetchedAt
    }
}
