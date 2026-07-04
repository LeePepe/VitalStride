// MY-874: training-in-progress row/section UI extracted to
// `ActiveWorkout/` (ActiveExerciseSection, SetRow, SubSetRow, SetTypeColor).
// This file keeps the session-level view. The ~25 remaining pre-existing
// `no_hardcoded_chinese` literals (titles, alert buttons, a11y labels/hints)
// predate the `--strict` hook and stay silenced at file scope until the
// dedicated i18n cleanup (MY-1065) migrates them. No semantic change.
// swiftlint:disable no_hardcoded_chinese
import HealthKitService
import os
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
import VitalUI

private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveWorkout")

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if !os(macOS)
    @Environment(\.healthKitService) private var healthKitService
    #endif
    @State private var workout: Workout?
    @State private var showingExercisePicker = false
    @State private var showingFinishAlert = false
    @State private var showingDiscardAlert = false
    @State private var exerciseToReplace: WorkoutExercise?
    @State private var restTimer = RestTimerController()
    @State private var currentHeartRate: Double?
    @State private var heartRateReceivedAt: Date?
    #if !os(macOS)
    @State private var sessionManager: (any WorkoutSessionManaging)?
    #endif
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    // MY-1088: workout-specific Large Mode toggle. Persisted across sessions.
    @AppStorage("activeWorkoutLargeMode") private var largeMode = false
    @State private var startTime = Date()
    let source: WorkoutStartSource

    init(source: WorkoutStartSource = .blank) {
        self.source = source
    }

    // MY-1088: header timer font. Stacks with the user's system Dynamic Type
    // via `.system(_ style:)` — Large Mode raises the base text style from
    // .title3 to .largeTitle; the system size then scales on top of that.
    private var timerFont: Font {
        Font.system(largeMode ? .largeTitle : .title3, design: .default)
            .monospacedDigit()
    }

    // MY-1088: header summary line ("N 动作 · M 组 · V kg") font. Same
    // Dynamic-Type-stacking approach as `timerFont`.
    private var summaryFont: Font {
        Font.system(largeMode ? .title3 : .subheadline, design: .default)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    workoutTimer
                    exerciseList
                }
                .snackbar(
                    isPresented: restSnackbarPresented,
                    mode: restTimer.phase == .completed ? .autoDismiss(duration: 2) : .persistent
                ) {
                    restSnackbarContent
                }
                addExerciseButton
                    .padding(.bottom, restTimer.phase != .idle ? 100 : 0)
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: restTimer.phase != .idle)
            }
            .navigationTitle("训练中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("放弃", role: .destructive) {
                        showingDiscardAlert = true
                    }
                }
                // MY-1088: Large Mode toggle. Persisted via @AppStorage above.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            largeMode.toggle()
                        }
                        HapticManager.trigger(.setCompleted)
                    } label: {
                        Image(
                            systemName: largeMode
                                ? "textformat.size.smaller"
                                : "textformat.size.larger"
                        )
                    }
                    .accessibilityLabel(
                        largeMode
                            ? String(
                                localized: "切换普通字号",
                                comment: "Active workout toggle: switch back to normal text size"
                            )
                            : String(
                                localized: "切换大字号",
                                comment: "Active workout toggle: switch to large text size"
                            )
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("结束训练") {
                        showingFinishAlert = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { exercises in
                    for exercise in exercises {
                        addExercise(exercise)
                    }
                }
            }
            .sheet(item: $exerciseToReplace) { workoutExercise in
                ExercisePickerView { newExercise in
                    workoutExercise.exercise = newExercise
                }
            }
            .alert("完成训练？", isPresented: $showingFinishAlert) {
                Button("完成") { finishWorkout() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("训练将被保存到历史记录")
            }
            .alert("放弃训练？", isPresented: $showingDiscardAlert) {
                Button("放弃", role: .destructive) { discardWorkout() }
                Button("继续训练", role: .cancel) {}
            } message: {
                Text("训练数据将不会保存")
            }
            .onAppear { setupWorkout() }
            .task(id: restTimer.restEndDate) {
                await restTimer.handleTimerTask()
            }
            .onChange(of: restTimer.phase) { _, newPhase in
                if newPhase == .completed {
                    HapticManager.trigger(.restCompleted)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .background else { return }
                do {
                    try modelContext.save()
                    logger.info("Background save triggered: result=success")
                } catch {
                    logger.info(
                        "Background save failed: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
            #if !os(macOS)
            .task { await observeHeartRate() }
            .task { await monitorHeartRateStaleness() }
            #endif
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var workoutTimer: some View {
        TimelineView(.periodic(from: startTime, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let totalSeconds = Int(elapsed)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            let timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            let exerciseCount = workout?.exercises?.count ?? 0
            let setCount = workout?.exercises?
                .reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0
            let volumeKg = totalVolumeKg
            let displayVolume = weightUnit == .lb ? volumeKg * 2.20462 : volumeKg
            let volumeText = Int(displayVolume).formatted()
            let summaryText = "\(exerciseCount) 动作 · \(setCount) 组 · \(volumeText) \(weightUnit.rawValue)"
            ViewThatFits(in: .horizontal) {
                HStack {
                    timerLabel
                    Text(timeString)
                        .font(timerFont)
                    #if !os(macOS)
                    heartRateLabel
                    #endif
                    Spacer()
                    Text(summaryText)
                        .font(summaryFont)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        timerLabel
                        Text(timeString)
                            .font(timerFont)
                        #if !os(macOS)
                        heartRateLabel
                        #endif
                        Spacer()
                    }
                    Text(summaryText)
                        .font(summaryFont)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, largeMode ? 16 : 8)
            .background(.bar)
        }
    }

    private var timerLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .foregroundStyle(.secondary)
            Text("训练时长")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    #if !os(macOS)
    private var heartRateLabel: some View {
        let bpmText = HeartRateFormatter.displayText(currentHeartRate)
        let unitText = String(localized: "次/分", comment: "Heart rate unit bpm")
        return HStack(spacing: 2) {
            Image(systemName: "heart.fill")
            Text(bpmText)
                .monospacedDigit()
            Text(unitText)
        }
        .font(.subheadline)
        .foregroundStyle(.pink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "心率", comment: "Heart rate a11y label"))
        .accessibilityValue(HeartRateFormatter.accessibilityText(currentHeartRate))
    }
    #endif

    private var restSnackbarPresented: Binding<Bool> {
        Binding(
            get: { restTimer.phase != .idle },
            set: { newValue in
                guard !newValue else { return }
                switch restTimer.phase {
                case .resting: restTimer.skipRest()
                case .completed: restTimer.dismissCompleted()
                case .idle: break
                }
            }
        )
    }

    @ViewBuilder
    private var restSnackbarContent: some View {
        if restTimer.phase == .completed {
            Button {
                restTimer.dismissCompleted()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "休息结束", comment: "Rest completed banner text"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "休息结束", comment: "Rest completed a11y label"))
            .accessibilityHint(String(localized: "点击关闭", comment: "Dismiss rest completed banner a11y hint"))
        } else if restTimer.phase == .resting, let restEnd = restTimer.restEndDate {
            let totalDuration = restTimer.restTotalDuration ?? 0
            let totalSeconds = max(1, Int(totalDuration))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(restEnd.timeIntervalSince(context.date)))
                let progress = 1.0 - Double(remaining) / Double(totalSeconds)
                HStack {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: progress)
                        Text("\(remaining)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(width: 32, height: 32)
                    .accessibilityElement(children: .ignore)
                    // swiftlint:disable:next line_length
                    .accessibilityLabel(String(localized: "休息中 \(remaining)s / \(totalSeconds)s", comment: "Rest timer progress a11y label"))
                    Spacer()
                    restAdjustButtons
                }
            }
        }
    }

    private var restAdjustButtons: some View {
        HStack(spacing: 8) {
            Button("-10s") {
                restTimer.adjustRest(by: -10)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .accessibilityLabel(String(localized: "缩短十秒", comment: "Subtract 10 seconds a11y label"))
            Button("+10s") {
                restTimer.adjustRest(by: 10)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .accessibilityLabel(String(localized: "延长十秒", comment: "Add 10 seconds a11y label"))
            Button(String(localized: "跳过", comment: "Skip rest button label")) {
                restTimer.skipRest()
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .accessibilityLabel(String(localized: "跳过休息", comment: "Skip rest a11y label"))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var exerciseList: some View {
        let exercises = (workout?.exercises ?? []).sorted { $0.order < $1.order }
        if exercises.isEmpty {
            ContentUnavailableView(
                "添加第一个动作",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("点击下方按钮选择训练动作")
            )
        } else {
            List {
                ForEach(exercises) { workoutExercise in
                    ActiveExerciseSection(
                        workoutExercise: workoutExercise,
                        onSetCompleted: {
                            restTimer.startRest()
                            TelemetryService.shared.trackNonisolated(
                                .setCompleted(exerciseName: TelemetryHelpers
                                    .exerciseIdentifier(workoutExercise.exercise))
                            )
                        },
                        onSetDeleted: {
                            TelemetryService.shared.trackNonisolated(.setDeleted)
                        },
                        onReplace: {
                            exerciseToReplace = workoutExercise
                        },
                        onDelete: {
                            deleteExercise(workoutExercise)
                        }
                    )
                }
                .onMove { source, destination in
                    moveExercises(from: source, to: destination)
                }
                Section {} footer: { Color.clear.frame(height: 72) }
            }
            // MY-877: plain list style + immediate keyboard dismissal on scroll
            // for compact, scannable in-workout entry. Reduce default row floor
            // so main SetRow targets ~36pt and SubSetRow targets ~28pt.
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .environment(\.defaultMinListRowHeight, 28)
        }
    }

    private var addExerciseButton: some View {
        Button {
            HapticManager.trigger(.exerciseAdded)
            showingExercisePicker = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(FABButtonStyle())
        .accessibilityLabel("添加动作")
        .padding()
    }

    private var totalVolumeKg: Double {
        (workout?.exercises ?? []).reduce(0.0) { $0 + $1.workingVolume }
    }

    // MARK: - Actions

    #if !os(macOS)
    private func observeHeartRate() async {
        for await dataPoint in healthKitService.observeHeartRate() {
            guard dataPoint.startDate.timeIntervalSinceNow > -120 else { continue }
            currentHeartRate = dataPoint.value
            heartRateReceivedAt = Date()
        }
    }

    private func monitorHeartRateStaleness() async {
        let freshnessLimit: TimeInterval = 120
        let checkInterval: Duration = .seconds(10)
        while !Task.isCancelled {
            try? await Task.sleep(for: checkInterval)
            if let receivedAt = heartRateReceivedAt,
               receivedAt.timeIntervalSinceNow < -freshnessLimit {
                currentHeartRate = nil
                heartRateReceivedAt = nil
            }
        }
    }
    #endif

    private func setupWorkout() {
        guard workout == nil else { return }

        let result = WorkoutResolver.resolve(
            source: source,
            startTime: startTime,
            using: modelContext
        )
        workout = result.workout
        startTime = result.startTime

        if case .resume = source {
            let exerciseCount = result.workout.exercises?.count ?? 0
            let setCount = result.workout.exercises?
                .reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0
            logger.info("Workout resumed: exerciseCount=\(exerciseCount), setCount=\(setCount)")
        }

        TelemetryService.shared.trackNonisolated(
            .workoutStarted(source: TelemetryHelpers.sourceIdentifier(source))
        )

        #if !os(macOS)
        let manager = healthKitService.makeWorkoutSessionManager()
        sessionManager = manager
        Task { await manager.startSession() }
        #endif
    }

    private func addExercise(_ exercise: Exercise) {
        guard let workout else { return }
        let order = workout.exercises?.count ?? 0
        let workoutExercise = WorkoutExercise(order: order, exercise: exercise)
        workoutExercise.workout = workout
        modelContext.insert(workoutExercise)

        let defaultSet = ExerciseSet(order: 0, weight: 0, reps: 0, setType: .working)
        defaultSet.workoutExercise = workoutExercise
        modelContext.insert(defaultSet)

        TelemetryService.shared.trackNonisolated(
            .exerciseAdded(name: TelemetryHelpers.exerciseIdentifier(exercise))
        )
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var exercises = (workout?.exercises ?? []).sorted { $0.order < $1.order }
        exercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in exercises.enumerated() {
            exercise.order = index
        }
    }

    private func deleteExercise(_ workoutExercise: WorkoutExercise) {
        modelContext.delete(workoutExercise)
        let remaining = (workout?.exercises ?? [])
            .filter { $0.persistentModelID != workoutExercise.persistentModelID }
            .sorted { $0.order < $1.order }
        for (index, exercise) in remaining.enumerated() {
            exercise.order = index
        }
    }

    private func finishWorkout() {
        guard let workout else { return }
        restTimer.cancelRestForWorkoutEnd()
        workout.finish()
        HapticManager.trigger(.workoutFinished)
        // MY-1088: pre-existing behavior, tracked separately from this issue.
        // swiftlint:disable:next silent_model_save
        try? modelContext.save()

        let exerciseCount = workout.exercises?.count ?? 0
        let setCount = workout.exercises?.reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0
        let durationSeconds = Int(Date().timeIntervalSince(startTime))
        TelemetryService.shared.trackNonisolated(.workoutCompleted(
            durationSeconds: max(0, durationSeconds),
            exerciseCount: exerciseCount,
            setCount: setCount
        ))

        #if !os(macOS)
        if let manager = sessionManager {
            Task {
                let healthKitUUID = await manager.endSession(save: true)
                if let healthKitUUID {
                    workout.healthKitUUID = healthKitUUID
                    // MY-1088: pre-existing behavior, tracked separately.
                    // swiftlint:disable:next silent_model_save
                    try? modelContext.save()
                }
                dismiss()
            }
            return
        }
        #endif
        dismiss()
    }

    private func discardWorkout() {
        restTimer.cancelRestForWorkoutEnd()
        #if !os(macOS)
        if let manager = sessionManager {
            Task { await manager.endSession(save: false) }
        }
        #endif
        if let workout {
            modelContext.delete(workout)
            // MY-1088: pre-existing behavior, tracked separately.
            // swiftlint:disable:next silent_model_save
            try? modelContext.save()
        }
        TelemetryService.shared.trackNonisolated(.workoutDiscarded)
        dismiss()
    }
}

// MARK: - Heart Rate Formatter

enum HeartRateFormatter {
    static func displayText(_ heartRate: Double?) -> String {
        guard let heartRate else { return "--" }
        return "\(Int(heartRate))"
    }

    static func accessibilityText(_ heartRate: Double?) -> String {
        guard let heartRate else {
            return String(localized: "无数据", comment: "No data a11y value")
        }
        let bpm = Int(heartRate)
        return String(localized: "\(bpm) 次每分钟", comment: "Heart rate a11y value with full unit")
    }
}

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MY-1088: preview wrapper. Seeds the `activeWorkoutLargeMode` @AppStorage
// key BEFORE `ActiveWorkoutView` initializes, so its own @AppStorage read
// picks up the seeded value and the Large Mode preview drives the same
// toolbar/render path as production instead of a synthetic environment.
private struct ActiveWorkoutPreview: View {
    init(largeMode: Bool) {
        UserDefaults.standard.set(largeMode, forKey: "activeWorkoutLargeMode")
    }
    var body: some View {
        ActiveWorkoutView()
            .modelContainer(try! ModelContainerConfiguration.makeTestContainer()) // swiftlint:disable:this force_try
    }
}

#Preview("Normal Mode") {
    ActiveWorkoutPreview(largeMode: false)
}

#Preview("Large Mode") {
    ActiveWorkoutPreview(largeMode: true)
}
