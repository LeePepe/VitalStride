// swiftlint:disable no_hardcoded_chinese
// MY-1269: Chinese string values are the xcstrings *source keys* that get
// resolved through Localizable.xcstrings via String(localized:) — that is the
// intended flow, not a hardcoded literal. Rule stays silenced at file scope
// until we migrate to ASCII key IDs (tracked in the follow-up i18n sub-issue).
import DesignKit
import HealthKitService
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels

enum AppTab: Hashable {
    // swiftlint:disable:next identifier_name
    case overview, workout, data, ai, settings
}

@Observable
final class AppNavigation {
    var selectedTab = AppTab.workout
    /// Set by `CrashRecoveryModifier` when the user chooses "恢复训练".
    /// `WorkoutListView` observes this, opens `ActiveWorkoutView` in resume
    /// mode, and clears it back to `nil`.
    var crashRecoveryResume: Workout?
    var showWorkoutLoadProgression = false
    var showStepsBodySettings = false

    init(selectedTab: AppTab = .workout) {
        self.selectedTab = selectedTab
    }
}

struct ContentView: View {
    static let visibleTabs: [AppTab] = [.workout, .settings]

    @State private var navigation: AppNavigation

    init(initialTab: AppTab = .workout) {
        self._navigation = State(initialValue: AppNavigation(selectedTab: initialTab))
    }

    var body: some View {
        @Bindable var nav = navigation
        TabView(selection: $nav.selectedTab) {
            Tab(String(localized: "训练", comment: ""), systemImage: "dumbbell.fill", value: .workout) {
                WorkoutListView()
            }
            .accessibilityLabel(String(localized: "训练", comment: "Workouts tab a11y label"))

            Tab(String(localized: "设置", comment: ""), systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
            .accessibilityLabel(String(localized: "设置", comment: "Settings tab a11y label"))
        }
        .environment(navigation)
        .detectsCrashRecovery(navigation: navigation)
        .onChange(of: nav.selectedTab) { _, newTab in
            TelemetryService.shared.trackNonisolated(
                .tabSwitched(tab: TelemetryHelpers.tabIdentifier(newTab))
            )
        }
    }
}

// MARK: - Unified Full-Flow Xcode Previews (1–6)

@MainActor
private enum ContentViewPreviewFixtures {
    private static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

    static let sampleHealthKitWorkouts: [HealthWorkoutRecord] = [
        HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: 37, // running
            duration: 45 * 60,
            totalEnergyBurned: 420,
            totalDistance: 8000,
            startDate: referenceDate.addingTimeInterval(-2 * 3600),
            endDate: referenceDate.addingTimeInterval(-2 * 3600 + 45 * 60),
            sourceName: "Apple Watch",
            averageHeartRate: 142,
            sourceDeviceKind: .appleWatch,
            isUserEntered: false
        ),
        HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: 52, // walking
            duration: 25 * 60,
            totalEnergyBurned: 90,
            totalDistance: 2200,
            startDate: referenceDate.addingTimeInterval(-6 * 3600),
            endDate: referenceDate.addingTimeInterval(-6 * 3600 + 25 * 60),
            sourceName: "iPhone",
            averageHeartRate: 108,
            sourceDeviceKind: .iPhone,
            isUserEntered: false
        ),
    ]

    static func makeSeededAppContainer() -> ModelContainer {
        // swiftlint:disable:next force_try
        let container = try! ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext

        let bench = Exercise(
            nameEn: "Barbell Bench Press",
            nameZh: "杠铃卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            primaryMuscles: ["pectoralis major"]
        )
        let squat = Exercise(
            nameEn: "Barbell Back Squat",
            nameZh: "杠铃深蹲",
            muscleGroup: .legs,
            equipment: .barbell,
            primaryMuscles: ["quadriceps"]
        )
        let latPulldown = Exercise(
            nameEn: "Lat Pulldown",
            nameZh: "高位下拉",
            muscleGroup: .back,
            equipment: .cable,
            primaryMuscles: ["latissimus dorsi"]
        )
        for exercise in [bench, squat, latPulldown] {
            context.insert(exercise)
        }

        let completedWorkout = Workout(
            type: .strength,
            startDate: referenceDate.addingTimeInterval(-3600),
            endDate: referenceDate.addingTimeInterval(-3600 + 52 * 60),
            totalCalories: 340,
            source: .recorded
        )
        context.insert(completedWorkout)

        let we1 = WorkoutExercise(order: 0, exercise: bench)
        we1.workout = completedWorkout
        context.insert(we1)

        let s1 = ExerciseSet(order: 0, weight: 60, reps: 10, setType: .working, isCompleted: true)
        s1.workoutExercise = we1
        let s2 = ExerciseSet(order: 1, weight: 65, reps: 8, setType: .working, isCompleted: true)
        s2.workoutExercise = we1
        context.insert(s1)
        context.insert(s2)

        let we2 = WorkoutExercise(order: 1, exercise: latPulldown)
        we2.workout = completedWorkout
        context.insert(we2)

        let s3 = ExerciseSet(order: 0, weight: 50, reps: 12, setType: .working, isCompleted: true)
        s3.workoutExercise = we2
        context.insert(s3)

        do {
            try context.save()
        } catch {
            assertionFailure("Preview container seed failed: \(error)")
        }
        return container
    }

    static func makeSeededPickerContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: Exercise.self, configurations: config)
        let context = container.mainContext

        let samples: [Exercise] = [
            Exercise(nameEn: "Barbell Bench Press", nameZh: "杠铃卧推", muscleGroup: .chest, equipment: .barbell, primaryMuscles: ["pectoralis major"]),
            Exercise(nameEn: "Incline Dumbbell Press", nameZh: "上斜哑铃卧推", muscleGroup: .chest, equipment: .dumbbell, primaryMuscles: ["pectoralis major"]),
            Exercise(nameEn: "Cable Chest Fly", nameZh: "龙门架夹胸", muscleGroup: .chest, equipment: .cable, primaryMuscles: ["pectoralis major"]),
            Exercise(nameEn: "Lat Pulldown", nameZh: "高位下拉", muscleGroup: .back, equipment: .cable, primaryMuscles: ["latissimus dorsi"]),
            Exercise(nameEn: "Barbell Bent-Over Row", nameZh: "杠铃俯身划船", muscleGroup: .back, equipment: .barbell, primaryMuscles: ["latissimus dorsi"]),
            Exercise(nameEn: "Dumbbell Shoulder Press", nameZh: "哑铃推举", muscleGroup: .shoulders, equipment: .dumbbell, primaryMuscles: ["deltoids"]),
            Exercise(nameEn: "Barbell Back Squat", nameZh: "杠铃深蹲", muscleGroup: .legs, equipment: .barbell, primaryMuscles: ["quadriceps"]),
            Exercise(nameEn: "Romanian Deadlift", nameZh: "罗马尼亚硬拉", muscleGroup: .legs, equipment: .barbell, primaryMuscles: ["hamstrings"]),
            Exercise(nameEn: "Dumbbell Bicep Curl", nameZh: "哑铃弯举", muscleGroup: .arms, equipment: .dumbbell, primaryMuscles: ["biceps brachii"]),
            Exercise(nameEn: "Hanging Leg Raise", nameZh: "悬垂举腿", muscleGroup: .core, equipment: .bodyweight, primaryMuscles: ["rectus abdominis"]),
        ]
        for item in samples {
            context.insert(item)
        }
        do {
            try context.save()
        } catch {
            assertionFailure("Picker preview container seed failed: \(error)")
        }
        return container
    }
}

#Preview("1. VitalStride · 双 Tab 完整体验") {
    ContentView()
        .environment(\.workoutListSnapshotMode, .populated)
        .environment(\.workoutListSnapshotRecords, ContentViewPreviewFixtures.sampleHealthKitWorkouts)
        .modelContainer(ContentViewPreviewFixtures.makeSeededAppContainer())
        .designThemePreview()
        .frame(width: 390, height: 844)
}

#Preview("2a. Tab 1 训练列表 · 混合数据 (Light)") {
    WorkoutListPreviewFixture(scenario: .mixed)
        .designThemePreview()
        .frame(width: 390, height: 844)
}

#Preview("2b. Tab 1 训练列表 · 混合数据 (Dark)") {
    WorkoutListPreviewFixture(scenario: .mixed)
        .preferredColorScheme(.dark)
        .designThemePreview()
        .frame(width: 390, height: 844)
}

#Preview("3a. 训练中 · 平铺模式 (Tiled)") {
    ActiveWorkoutPreview(largeMode: false)
        .frame(width: 390, height: 844)
}

#Preview("3b. 训练中 · 大字模式 (Focus)") {
    ActiveWorkoutPreview(largeMode: true)
        .frame(width: 390, height: 844)
}

#Preview("4a. 动作选择 · P0-P3 折叠底栏 (Light)") {
    ExercisePickerView(onConfirm: { _ in })
        .modelContainer(ContentViewPreviewFixtures.makeSeededPickerContainer())
        .designTheme()
        .frame(width: 390, height: 844)
}

#Preview("4b. 动作选择 · P0-P3 折叠底栏 (Dark)") {
    ExercisePickerView(onConfirm: { _ in })
        .modelContainer(ContentViewPreviewFixtures.makeSeededPickerContainer())
        .preferredColorScheme(.dark)
        .designTheme()
        .frame(width: 390, height: 844)
}

#if canImport(UIKit) && !os(macOS)
#Preview("5. 训练键盘 · 重量输入 (Working Set)") {
    VStack(spacing: 0) {
        Spacer()
        WorkoutNumericKeyboardContentView(
            field: .weight,
            setType: .working,
            exercise: nil,
            recentWeightKg: 40,
            suggestedWeightKg: 42.5,
            suggestedReps: 8,
            theme: Theme(seed: .teal, neutral: .slate, isDark: false),
            onKeyPress: { _ in },
            onLeftAction: { _ in },
            onPresetReps: { _, _ in },
            onDone: {}
        )
        .frame(height: 300)
    }
    .frame(width: 390, height: 844)
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif

#Preview("6. Tab 2 · 设置页 (Settings)") {
    ContentView(initialTab: .settings)
        .modelContainer(ContentViewPreviewFixtures.makeSeededAppContainer())
        .designThemePreview()
        .frame(width: 390, height: 844)
}
