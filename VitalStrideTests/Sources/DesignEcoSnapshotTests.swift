import DesignKit
import SwiftData
import SwiftUI
import XCTest
import VitalModels

#if canImport(UIKit) && !os(macOS)
import UIKit

@testable import VitalStride

@MainActor
final class DesignEcoSnapshotTests: XCTestCase {
    private static let snapshotSize = CGSize(width: 393, height: 852)
    private static let snapshotNames = [
        "workout-normal-keyboard",
        "workout-large-font",
        "substitute-sheet",
        "exercise-picker",
    ].flatMap { [$0, "\($0)-dark"] }

    func testRendersRoundTwoSnapshots() throws {
        let outputDirectory = try Self.prepareOutputDirectory()
        let workoutFixture = try Self.makeWorkoutFixture()
        let defaultsSuite = "DesignEcoSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        for variant in [SnapshotVariant.light, .dark] {
            try Self.renderRoundTwoScreens(
                variant: variant,
                outputDirectory: outputDirectory,
                workoutFixture: workoutFixture,
                defaults: defaults
            )
        }

        for name in Self.snapshotNames {
            let url = outputDirectory.appendingPathComponent("\(name).png")
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 10_000)
        }
    }

    private enum SnapshotVariant: Equatable {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light:
                .light
            case .dark:
                .dark
            }
        }

        var isDark: Bool {
            self == .dark
        }

        var suffix: String {
            self == .dark ? "-dark" : ""
        }
    }

    private static func renderRoundTwoScreens(
        variant: SnapshotVariant,
        outputDirectory: URL,
        workoutFixture: WorkoutFixture,
        defaults: UserDefaults
    ) throws {
        let suffix = variant.suffix
        defaults.set(false, forKey: "activeWorkoutLargeMode")
        try Self.render(
            VStack(spacing: 0) {
                ActiveWorkoutView(source: .resume(workoutFixture.workout))
                    .frame(height: 560)
                WorkoutNumericKeyboardContentView(
                    field: .weight,
                    setType: .working,
                    exercise: workoutFixture.exercise,
                    recentWeightKg: 40,
                    theme: Theme(seed: .teal, neutral: .slate, isDark: variant.isDark),
                    onKeyPress: { _ in },
                    onLeftAction: { _ in },
                    onPresetReps: { _, _ in },
                    onDone: {}
                )
                .frame(height: 292)
            }
            .modelContainer(workoutFixture.container)
            .designTheme(seed: .teal, neutral: .slate)
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: variant.isDark))
            .defaultAppStorage(defaults),
            named: "workout-normal-keyboard\(suffix)",
            in: outputDirectory,
            variant: variant
        )

        defaults.set(true, forKey: "activeWorkoutLargeMode")
        try Self.render(
            ActiveWorkoutView(source: .resume(workoutFixture.workout))
                .modelContainer(workoutFixture.container)
                .designTheme(seed: .teal, neutral: .slate)
                .environment(\.colorScheme, variant.colorScheme)
            .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: variant.isDark))
            .defaultAppStorage(defaults),
            named: "workout-large-font\(suffix)",
            in: outputDirectory,
            variant: variant
        )

        try Self.render(
            ExerciseSubstituteSheet(
                state: .results([
                    .init(
                        id: "band-hip-extension",
                        name: "弹力带俯身髋部伸展",
                        muscleGroup: "臀腿",
                        reason: "动作轨迹相近，器械要求更低，适合在家训练。"
                    ),
                    .init(
                        id: "cable-pull-through",
                        name: "绳索 pull-through",
                        muscleGroup: "臀腿",
                        reason: "髋部主导发力，顶峰收缩清晰。"
                    ),
                    .init(
                        id: "bodyweight-good-morning",
                        name: "徒手早安式",
                        muscleGroup: "后链",
                        reason: "无器械时的轻量替代动作。"
                    ),
                ]),
                onSelect: { _ in },
                onManualSelect: {}
            )
            .designTheme(seed: .teal, neutral: .slate)
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: variant.isDark)),
            named: "substitute-sheet\(suffix)",
            in: outputDirectory,
            variant: variant
        )

        let pickerContainer = try Self.makePickerContainer()
        try Self.render(
            ExercisePickerView(onConfirm: { _ in })
                .modelContainer(pickerContainer)
                .designTheme(seed: .teal, neutral: .slate)
                .environment(\.colorScheme, variant.colorScheme)
                .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: variant.isDark)),
            named: "exercise-picker\(suffix)",
            in: outputDirectory,
            variant: variant
        )
    }

    private static func prepareOutputDirectory() throws -> URL {
        let directory: URL
        if let path = ProcessInfo.processInfo.environment["DESIGN_ECO_SNAPSHOT_DIR"] {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "design-eco-snapshots/round-2",
                isDirectory: true
            )
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func render<Content: View>(
        _ content: Content,
        named name: String,
        in directory: URL,
        variant: SnapshotVariant
    ) throws {
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = variant.isDark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: snapshotSize)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        if name.hasPrefix("workout-normal-keyboard") {
            NotificationCenter.default.post(
                name: UIResponder.keyboardWillShowNotification,
                object: nil
            )
        }
        defer {
            window.rootViewController = nil
            window.isHidden = true
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: snapshotSize, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 10_000)
        try data.write(
            to: directory.appendingPathComponent("\(name).png"),
            options: .atomic
        )
    }

    private struct WorkoutFixture {
        let container: ModelContainer
        let workout: Workout
        let exercise: Exercise
    }

    private static func makeWorkoutFixture() throws -> WorkoutFixture {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        let secondExercise = Exercise(
            nameEn: "Cable Row",
            nameZh: "坐姿绳索划船",
            muscleGroup: .back,
            equipment: .cable
        )
        let sets = [
            ExerciseSet(order: 0, weight: 40, reps: 10, isCompleted: true),
            ExerciseSet(order: 1, weight: 42.5, reps: 8),
            ExerciseSet(order: 2, weight: 42.5, reps: 8),
        ]
        let secondSet = ExerciseSet(order: 0, weight: 35, reps: 12, isCompleted: true)
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: sets)
        let secondWorkoutExercise = WorkoutExercise(
            order: 1,
            exercise: secondExercise,
            sets: [secondSet]
        )
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-32),
            exercises: [workoutExercise, secondWorkoutExercise]
        )

        context.insert(exercise)
        context.insert(secondExercise)
        context.insert(workout)
        context.insert(workoutExercise)
        context.insert(secondWorkoutExercise)
        for set in sets + [secondSet] {
            context.insert(set)
        }
        try context.save()
        return WorkoutFixture(container: container, workout: workout, exercise: exercise)
    }

    private static func makePickerContainer() throws -> ModelContainer {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let exercises = [
            Exercise(nameEn: "Bench Press", nameZh: "卧推", muscleGroup: .chest, equipment: .barbell),
            Exercise(nameEn: "Band Hip Extension", nameZh: "弹力带髋伸展", muscleGroup: .legs, equipment: .band),
            Exercise(nameEn: "Cable Row", nameZh: "坐姿绳索划船", muscleGroup: .back, equipment: .cable),
            Exercise(nameEn: "Goblet Squat", nameZh: "高脚杯深蹲", muscleGroup: .legs, equipment: .dumbbell),
            Exercise(nameEn: "Push Up", nameZh: "俯卧撑", muscleGroup: .chest, equipment: .bodyweight),
            Exercise(nameEn: "Lat Pulldown", nameZh: "高位下拉", muscleGroup: .back, equipment: .machine),
            Exercise(nameEn: "Kettlebell Press", nameZh: "壶铃推举", muscleGroup: .shoulders, equipment: .kettlebell),
            Exercise(nameEn: "Medicine Ball Slam", nameZh: "药球砸地", muscleGroup: .core, equipment: .medicineBall),
        ]
        exercises.forEach(context.insert)
        try context.save()
        return container
    }
}

#endif
