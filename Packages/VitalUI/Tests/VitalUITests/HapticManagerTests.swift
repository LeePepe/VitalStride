import Testing
@testable import VitalUI

@Suite("HapticManager")
struct HapticManagerTests {
    @Test("HapticType has exactly 4 cases")
    func hapticTypeCaseCount() {
        #expect(HapticType.allCases.count == 4)
    }

    @Test("HapticType includes all expected cases")
    func hapticTypeContainsExpectedCases() {
        let cases = HapticType.allCases
        #expect(cases.contains(.setCompleted))
        #expect(cases.contains(.restCompleted))
        #expect(cases.contains(.exerciseAdded))
        #expect(cases.contains(.workoutFinished))
    }

    @Test("trigger does not crash for any haptic type", arguments: HapticType.allCases)
    @MainActor
    func triggerDoesNotCrash(type: HapticType) {
        HapticManager.trigger(type)
    }
}
