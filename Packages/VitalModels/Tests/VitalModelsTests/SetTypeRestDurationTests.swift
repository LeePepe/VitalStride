import Foundation
import Testing
@testable import VitalModels

@Suite("SetType.defaultRestDuration mapping")
struct SetTypeRestDurationTests {

    @Test("warmup default rest = 45s")
    func warmupDefault() {
        #expect(SetType.warmup.defaultRestDuration == 45)
    }

    @Test("working default rest = 120s")
    func workingDefault() {
        #expect(SetType.working.defaultRestDuration == 120)
    }

    @Test("dropSet default rest = 15s")
    func dropSetDefault() {
        #expect(SetType.dropSet.defaultRestDuration == 15)
    }

    @Test("pyramid default rest = 75s")
    func pyramidDefault() {
        #expect(SetType.pyramid.defaultRestDuration == 75)
    }

    /// Exhaustive guard: every SetType case must be covered by the mapping
    /// above. If a new case is added without extending the expected table,
    /// this test fails so the mapping cannot silently miss coverage.
    @Test("allCases exhaustive mapping guard")
    func exhaustiveMapping() {
        let expected: [SetType: TimeInterval] = [
            .warmup: 45,
            .working: 120,
            .dropSet: 15,
            .pyramid: 75,
        ]

        #expect(SetType.allCases.count == expected.count)
        for setType in SetType.allCases {
            let expectedValue = expected[setType]
            #expect(expectedValue != nil, "SetType.\(setType) missing from expected mapping")
            #expect(setType.defaultRestDuration == expectedValue)
        }
    }
}
