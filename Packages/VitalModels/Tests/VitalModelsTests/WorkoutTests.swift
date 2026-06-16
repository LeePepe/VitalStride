import Foundation
import Testing
@testable import VitalModels

@Suite("Workout Tests")
struct WorkoutTests {
    @Test("isInProgress returns true when endDate is nil and source is .recorded")
    func isInProgressWhenActive() {
        let workout = Workout(type: .strength, startDate: Date(), source: .recorded)
        #expect(workout.isInProgress == true)
    }

    @Test("isInProgress returns false when endDate is set")
    func isNotInProgressWhenFinished() {
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date(),
            source: .recorded
        )
        #expect(workout.isInProgress == false)
    }

    @Test("isInProgress returns false when source is .imported")
    func isNotInProgressWhenImported() {
        let workout = Workout(type: .strength, startDate: Date(), source: .imported)
        #expect(workout.isInProgress == false)
    }

    @Test("isInProgress returns false when source is .healthkit")
    func isNotInProgressWhenHealthKit() {
        let workout = Workout(type: .strength, startDate: Date(), source: .healthkit)
        #expect(workout.isInProgress == false)
    }

    @Test("isInProgress returns false when endDate is set and source is .imported")
    func isNotInProgressWhenFinishedAndImported() {
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date(),
            source: .imported
        )
        #expect(workout.isInProgress == false)
    }
}
