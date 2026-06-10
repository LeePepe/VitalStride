import AIService
import Foundation

enum OverviewLayoutState: Sendable {
    case loading
    case dynamic([OverviewInsight], lastUpdated: Date?)
    case fallback
}
