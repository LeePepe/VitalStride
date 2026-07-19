import Foundation
import SwiftData
import Testing
@testable import VitalModels

@Suite("Exercise SwiftData persistence")
struct ExercisePersistenceTests {

    @Test("mediaKey survives SwiftData insert/save/fetch round-trip")
    func mediaKeyRoundTrip() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            mediaKey: "bench-press-001"
        )
        context.insert(exercise)
        try context.save()

        let fetchContext = ModelContext(container)
        let results = try fetchContext.fetch(FetchDescriptor<Exercise>())

        #expect(results.count == 1)
        let fetched = try #require(results.first)
        #expect(fetched.mediaKey == "bench-press-001")
        #expect(fetched.nameEn == "Bench Press")
        #expect(fetched.nameZh == "卧推")
    }

    @Test("nil mediaKey survives SwiftData round-trip as nil")
    func nilMediaKeyRoundTrip() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Push Up",
            nameZh: "俯卧撑",
            muscleGroup: .chest,
            equipment: .bodyweight
        )
        context.insert(exercise)
        try context.save()

        let fetchContext = ModelContext(container)
        let results = try fetchContext.fetch(FetchDescriptor<Exercise>())

        #expect(results.count == 1)
        let fetched = try #require(results.first)
        #expect(fetched.mediaKey == nil)
    }
}
