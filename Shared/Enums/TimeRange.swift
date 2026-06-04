import Foundation

enum TimeRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .day: String(localized: "日", comment: "Time range: day")
        case .week: String(localized: "周", comment: "Time range: week")
        case .month: String(localized: "月", comment: "Time range: month")
        case .year: String(localized: "年", comment: "Time range: year")
        }
    }

    func dateInterval(from referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let end = calendar.startOfDay(for: referenceDate).addingTimeInterval(86400)
        let start: Date
        switch self {
        case .day:
            start = calendar.startOfDay(for: referenceDate)
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate))!
        case .month:
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: referenceDate))!
        case .year:
            start = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: referenceDate))!
        }
        return DateInterval(start: start, end: end)
    }
}
