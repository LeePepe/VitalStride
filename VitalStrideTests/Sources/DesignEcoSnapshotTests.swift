import DesignKit
import SwiftData
import SwiftUI
import XCTest
import VitalModels

#if canImport(UIKit) && !os(macOS)
import ImageIO
import UIKit
import UniformTypeIdentifiers

@testable import VitalStride

@MainActor
final class DesignEcoSnapshotTests: XCTestCase {
    private static let snapshotSize = CGSize(width: 393, height: 852)
    private static let snapshotNames = [
        "workout-normal-keyboard",
        "workout-normal-keyboard-dark",
        "workout-large-font",
        "workout-large-font-dark",
        "workout-rtl",
        "exercise-header-normal-light",
        "exercise-header-normal-dark",
        "exercise-header-large-light",
        "exercise-header-large-dark",
        "exercise-header-normal-rtl",
        "exercise-header-large-rtl",
        "substitute-sheet",
        "substitute-sheet-dark",
        "exercise-picker",
        "exercise-picker-dark",
        "exercise-picker-rtl",
    ]

    func testRendersRoundThreeSnapshots() throws {
        let outputDirectory = try Self.prepareOutputDirectory()
        let workoutFixture = try Self.makeWorkoutFixture()
        let defaultsSuite = "DesignEcoSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        for variant in [SnapshotVariant.light, .dark] {
            try Self.renderRoundThreeScreens(
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

    @MainActor
    private final class HeaderFrames {
        var controls: [AnyHashable: [String: CGRect]] = [:]
        var headers: [AnyHashable: CGRect] = [:]
        var geometry: (listFrame: CGRect, contentOffset: CGPoint)?
        var rows: [AnyHashable: CGRect] = [:]
    }

    func testExerciseHeadersAdaptToTitleWidthAndDynamicType() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DesignEcoHeaderLayout"))
        defaults.set(false, forKey: "activeWorkoutLargeMode")
        defer { defaults.removePersistentDomain(forName: "DesignEcoHeaderLayout") }
        let cases: [(String, Bool, DynamicTypeSize, Bool)] = [
            ("卧推", false, .large, true),
            ("坐姿绳索划船", true, .large, true),
            ("Band Bent-Over Row (Cable)", false, .large, false),
            ("卧推", false, .accessibility3, false),
        ]
        for (name, completed, typeSize, compact) in cases {
            let fixture = try Self.makeWorkoutFixture()
            fixture.exercise.nameEn = name
            fixture.exercise.nameZh = name
            let owner = try XCTUnwrap(fixture.workout.exercises?.first { $0.order == 0 })
            for exerciseSet in owner.sets ?? [] { exerciseSet.isCompleted = completed }
            let frames = HeaderFrames()
            let content = ActiveWorkoutView(source: .resume(fixture.workout))
                .modelContainer(fixture.container)
                .designTheme(seed: .teal, neutral: .slate)
                .dynamicTypeSize(typeSize)
                .defaultAppStorage(defaults)
                .environment(\.activeWorkoutListObservation, ActiveWorkoutListObservationSink(
                    onHeaderFrame: { frames.headers[$0] = $1 },
                    onControlFrame: { frames.controls[$0, default: [:]][$1] = $2 }
                ))
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(origin: .zero, size: Self.snapshotSize))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            try await Task.sleep(for: .milliseconds(350))
            host.view.layoutIfNeeded()
            let controls = try XCTUnwrap(frames.controls[owner.persistentModelID])
            let title = try XCTUnwrap(controls["title"])
            let progress = try XCTUnwrap(controls["progress"])
            let addSet = try XCTUnwrap(controls["add-set"])
            let menu = try XCTUnwrap(controls["menu"])
            XCTAssertFalse(title.intersects(progress), name)
            XCTAssertFalse(title.intersects(addSet), name)
            XCTAssertFalse(addSet.intersects(menu), name)
            XCTAssertGreaterThanOrEqual(addSet.width, 44, name)
            XCTAssertGreaterThanOrEqual(addSet.height, 44, name)
            XCTAssertLessThan(title.minY, addSet.maxY, name)
            XCTAssertGreaterThan(title.maxY, addSet.minY, name)
            let header = try XCTUnwrap(frames.headers[owner.persistentModelID])
            XCTAssertLessThanOrEqual(header.height, 44, name)
        }
    }

    func testTK3HeaderControlsContainmentNormalLargeLTRRTL() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DesignEcoTK3Containment"))
        defer { defaults.removePersistentDomain(forName: "DesignEcoTK3Containment") }

        for largeMode in [false, true] {
            for rightToLeft in [false, true] {
                defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                let fixture = try Self.makeWorkoutFixture()
                fixture.exercise.nameEn = "Band Bent-Over Hip Extension"
                fixture.exercise.nameZh = "弹力带俯身髋部伸展"
                let owner = try XCTUnwrap(fixture.workout.exercises?.first { $0.order == 0 })
                let frames = HeaderFrames()
                let content = ActiveWorkoutView(source: .resume(fixture.workout))
                    .modelContainer(fixture.container)
                    .designTheme(seed: .teal, neutral: .slate)
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                    .environment(\.activeWorkoutListObservation, ActiveWorkoutListObservationSink(
                        onGeometry: { geometry in
                            frames.geometry = (geometry.listFrame, geometry.contentOffset)
                        },
                        onHeaderFrame: { frames.headers[$0] = $1 },
                        onControlFrame: { frames.controls[$0, default: [:]][$1] = $2 }
                    ))
                    .defaultAppStorage(defaults)
                let host = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(origin: .zero, size: Self.snapshotSize))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                try await Task.sleep(for: .milliseconds(350))
                host.view.layoutIfNeeded()

                let header = try XCTUnwrap(frames.headers[owner.persistentModelID])
                let controls = try XCTUnwrap(frames.controls[owner.persistentModelID])
                for name in ["order", "add-set", "menu"] {
                    let frame = try XCTUnwrap(controls[name], "Missing \(name)")
                    if name != "order" {
                        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(name) width")
                        XCTAssertGreaterThanOrEqual(frame.height, 44, "\(name) height")
                    }
                    XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(frame),
                                  "\(largeMode ? "large" : "normal") \(rightToLeft ? "RTL" : "LTR") \(name) frame=\(frame) window=\(window.bounds)")
                    XCTAssertTrue(header.insetBy(dx: -1, dy: -1).contains(frame),
                                  "\(name) must stay in header bounds")
                }
            }
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

    private static func renderRoundThreeScreens(
        variant: SnapshotVariant,
        outputDirectory: URL,
        workoutFixture: WorkoutFixture,
        defaults: UserDefaults
    ) throws {
        let suffix = variant.suffix
        for largeMode in [false, true] {
            defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
            try Self.render(
                ActiveWorkoutView(source: .resume(workoutFixture.workout))
                    .frame(height: 560)
                    .modelContainer(workoutFixture.container)
                    .designTheme(seed: .teal, neutral: .slate)
                    .environment(\.colorScheme, variant.colorScheme)
                    .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: variant.isDark))
                    .defaultAppStorage(defaults),
                named: "exercise-header-\(largeMode ? "large" : "normal")-\(variant.isDark ? "dark" : "light")",
                in: outputDirectory,
                variant: variant
            )
        }
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

        defaults.set(false, forKey: "activeWorkoutLargeMode")
        if variant == .light {
            try Self.render(
                ActiveWorkoutView(source: .resume(workoutFixture.workout))
                    .modelContainer(workoutFixture.container)
                    .designTheme(seed: .teal, neutral: .slate)
                    .environment(\.colorScheme, .light)
                    .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: false))
                    .environment(\.layoutDirection, .rightToLeft)
                    .defaultAppStorage(defaults),
                named: "workout-rtl",
                in: outputDirectory,
                variant: .light
            )
            for largeMode in [false, true] {
                defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                try Self.render(
                    ActiveWorkoutView(source: .resume(workoutFixture.workout))
                        .frame(height: 560)
                        .modelContainer(workoutFixture.container)
                        .designTheme(seed: .teal, neutral: .slate)
                        .environment(\.colorScheme, .light)
                        .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: false))
                        .environment(\.layoutDirection, .rightToLeft)
                        .defaultAppStorage(defaults),
                    named: "exercise-header-\(largeMode ? "large" : "normal")-rtl",
                    in: outputDirectory,
                    variant: .light
                )
            }
        }

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

        if variant == .light {
            try Self.render(
                ExercisePickerView(onConfirm: { _ in })
                    .modelContainer(pickerContainer)
                    .designTheme(seed: .teal, neutral: .slate)
                    .environment(\.colorScheme, .light)
                    .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: false))
                    .environment(\.layoutDirection, .rightToLeft),
                named: "exercise-picker-rtl",
                in: outputDirectory,
                variant: .light
            )
        }
    }

    private static func prepareOutputDirectory() throws -> URL {
        let directory: URL
        if let path = ProcessInfo.processInfo.environment["DESIGN_ECO_SNAPSHOT_DIR"]
            ?? ProcessInfo.processInfo.environment["SIMCTL_CHILD_DESIGN_ECO_SNAPSHOT_DIR"] {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = URL(
                fileURLWithPath: "/Users/lee/Development/handoff/design-eco-r4/snapshots/TK3-VS-HEADER",
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
        window.overrideUserInterfaceStyle = variant.isDark ? .dark : .light
        window.makeKeyAndVisible()
        if name.hasPrefix("workout-normal-keyboard") {
            NotificationCenter.default.post(
                name: UIResponder.keyboardWillShowNotification,
                object: nil
            )
        }
        defer {
            if name.hasPrefix("workout-normal-keyboard") {
                NotificationCenter.default.post(
                    name: UIResponder.keyboardWillHideNotification,
                    object: nil
                )
            }
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
        // Embed render provenance so a fresh export is distinguishable even
        // when an unchanged screen reproduces exactly the same pixels.
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        let metadata = [kCGImagePropertyPNGDictionary: [
            kCGImagePropertyPNGDescription: "\(name); rendered \(Date().ISO8601Format())"
        ]]
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (output as Data).write(
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
            nameZh: "弹力带俯身髋部伸展",
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
            ExerciseSet(order: 0, weight: 40, reps: 10, setType: .warmup, isCompleted: true),
            ExerciseSet(order: 1, weight: 42.5, reps: 8, rpe: 8),
            ExerciseSet(order: 2, weight: 36, reps: 8, setType: .dropSet),
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
            Exercise(nameEn: "Barbell Row", nameZh: "杠铃划船", muscleGroup: .back, equipment: .barbell),
            Exercise(nameEn: "Band Hip Extension", nameZh: "弹力带髋伸展", muscleGroup: .legs, equipment: .band),
            Exercise(nameEn: "Band Pull Apart", nameZh: "弹力带拉伸", muscleGroup: .shoulders, equipment: .band),
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
