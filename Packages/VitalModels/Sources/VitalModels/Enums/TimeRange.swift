import Foundation

public enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    public var id: String { rawValue }

    public var formattedInterval: String {
        let interval = dateInterval()
        let start = interval.start
        let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        switch self {
        case .day:
            return start.formatted(.dateTime.month().day())
        case .week, .month:
            return "\(start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
        case .year:
            return "\(start.formatted(.dateTime.year().month())) – \(end.formatted(.dateTime.year().month()))"
        }
    }

    public var localizedLabel: String {
        switch self {
        case .day: String(localized: "日", comment: "Time range: day")
        case .week: String(localized: "周", comment: "Time range: week")
        case .month: String(localized: "月", comment: "Time range: month")
        case .year: String(localized: "年", comment: "Time range: year")
        }
    }

    public func dateInterval(from referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 1, to: startOfReferenceDay)!
        let start: Date
        switch self {
        case .day:
            start = startOfReferenceDay
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: startOfReferenceDay)!
        case .month:
            start = calendar.date(byAdding: .month, value: -1, to: startOfReferenceDay)!
        case .year:
            start = calendar.date(byAdding: .year, value: -1, to: startOfReferenceDay)!
        }
        return DateInterval(start: start, end: end)
    }
}
