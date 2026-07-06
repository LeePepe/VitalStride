import Foundation
import Testing

@testable import VitalStride

@Suite("WorkoutCalendarViewMode")
struct WorkoutCalendarViewModeTests {
    @Test("Raw values round-trip for all cases")
    func rawValueRoundTrip() {
        #expect(ViewMode(rawValue: ViewMode.list.rawValue) == .list)
        #expect(ViewMode(rawValue: ViewMode.calendar.rawValue) == .calendar)
    }

    @Test("Missing or empty persisted raw value maps to .list default")
    func missingOrEmptyRawValueDefaultsToList() {
        // @SceneStorage resolves an absent value via its declared default. To
        // pin the FR-004 / SC-003 default (List), assert both the raw-value
        // lookup returns nil for unknown/empty input AND the caller-side
        // fallback lands on `.list`.
        let missingRaw: String? = nil
        let emptyRaw = ""
        let unknownRaw = "grid"

        let resolvedFromMissing = missingRaw.flatMap(ViewMode.init(rawValue:)) ?? .list
        let resolvedFromEmpty = ViewMode(rawValue: emptyRaw) ?? .list
        let resolvedFromUnknown = ViewMode(rawValue: unknownRaw) ?? .list

        #expect(ViewMode(rawValue: emptyRaw) == nil)
        #expect(ViewMode(rawValue: unknownRaw) == nil)
        #expect(resolvedFromMissing == .list)
        #expect(resolvedFromEmpty == .list)
        #expect(resolvedFromUnknown == .list)
    }

    @Test("CaseIterable exposes exactly list and calendar")
    func caseIterableCoversBothModes() {
        #expect(ViewMode.allCases.count == 2)
        #expect(ViewMode.allCases.contains(.list))
        #expect(ViewMode.allCases.contains(.calendar))
    }
}
