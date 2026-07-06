import Foundation
import Testing
@testable import VitalModels

@Suite("WorkoutTemplate estimatedDuration Tests")
struct WorkoutTemplateDurationTests {
    @Test("empty template returns 0")
    func emptyTemplateReturnsZero() {
        let template = WorkoutTemplate(name: "Empty")
        #expect(template.estimatedDuration(historicalAverage: nil) == 0)
    }

    @Test("template with nil exercises returns 0")
    func nilExercisesReturnsZero() {
        let template = WorkoutTemplate(name: "Nil")
        template.exercises = nil
        #expect(template.estimatedDuration(historicalAverage: nil) == 0)
    }

    @Test("template with exercises but zero targetSets returns 0")
    func zeroSetsReturnsZero() {
        let template = WorkoutTemplate(
            name: "ZeroSets",
            exercises: [
                TemplateExercise(targetSets: 0, order: 0),
                TemplateExercise(targetSets: 0, order: 1)
            ]
        )
        #expect(template.estimatedDuration(historicalAverage: nil) == 0)
    }

    @Test("empirical estimate is totalSets * 90s + 5min transition")
    func empiricalEstimate() {
        let template = WorkoutTemplate(
            name: "Twelve Sets",
            exercises: [
                TemplateExercise(targetSets: 4, order: 0),
                TemplateExercise(targetSets: 4, order: 1),
                TemplateExercise(targetSets: 4, order: 2)
            ]
        )
        let expected: TimeInterval = 12 * 90 + 5 * 60
        #expect(template.estimatedDuration(historicalAverage: nil) == expected)
    }

    @Test("historical average is preferred over empirical formula")
    func historicalPreferredOverEmpirical() {
        let template = WorkoutTemplate(
            name: "With History",
            exercises: [
                TemplateExercise(targetSets: 4, order: 0),
                TemplateExercise(targetSets: 4, order: 1),
                TemplateExercise(targetSets: 4, order: 2)
            ]
        )
        let historical: TimeInterval = 30 * 60
        #expect(template.estimatedDuration(historicalAverage: historical) == historical)
    }

    @Test("zero historical average falls back to empirical formula")
    func zeroHistoricalFallsBack() {
        let template = WorkoutTemplate(
            name: "Zero History",
            exercises: [
                TemplateExercise(targetSets: 2, order: 0)
            ]
        )
        let expected: TimeInterval = 2 * 90 + 5 * 60
        #expect(template.estimatedDuration(historicalAverage: 0) == expected)
    }

    @Test("negative historical average falls back to empirical formula")
    func negativeHistoricalFallsBack() {
        let template = WorkoutTemplate(
            name: "Negative History",
            exercises: [
                TemplateExercise(targetSets: 2, order: 0)
            ]
        )
        let expected: TimeInterval = 2 * 90 + 5 * 60
        #expect(template.estimatedDuration(historicalAverage: -100) == expected)
    }

    @Test("empty template still returns 0 even if historical average provided")
    func emptyTemplateWithHistoryStillZero() {
        let template = WorkoutTemplate(name: "Empty With History")
        #expect(template.estimatedDuration(historicalAverage: 1000) == 0)
    }
}
