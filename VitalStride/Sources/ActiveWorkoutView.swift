// swiftlint:disable no_hardcoded_chinese
import AIService
import FlightKit
import HealthKitService
import os
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
import VitalUI

private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveWorkout")

#if canImport(UIKit)
import UIKit
#endif

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if !os(macOS)
    @Environment(\.healthKitService) private var healthKitService
    #endif
    // Spec 019 Stage 3c (T017/T018): sink for the substitute request's
    // `RoutingSignal`, and the retro-write target for `accepted` after the
    // user applies or cancels a suggestion.
    @Environment(\.routingSignalStore) private var signalStore
    @Environment(\.flightStore) private var flightStore
    @State private var workout: Workout?
    @State private var showingExercisePicker = false
    @State private var selectedExerciseID: PersistentIdentifier?
    @State private var isSidebarReordering = false
    @State private var draggedSidebarExerciseID: PersistentIdentifier?
    @State private var showingFinishAlert = false
    @State private var showingDiscardAlert = false
    @State private var exerciseToReplace: WorkoutExercise?
    @State private var exerciseToSubstitute: WorkoutExercise?
    @State private var substituteManualFallback: WorkoutExercise?
    @State private var substituteSheetState: ExerciseSubstituteSheet.ViewState = .loading
    @State private var substituteLoadTask: Task<Void, Never>?
    @State private var restTimer = RestTimerController()
    /// MY-1420: owns the 5s undo window for set deletion. Held at view level
    /// (not per section) so one delete anywhere in the workout replaces any
    /// other pending undo — undos never stack — and so a single bottom
    /// snackbar can arbitrate against the rest timer.
    @State private var undoController = SetDeletionUndoController()
    // MY-1283: three-state HR model (T003). `hrConnectionState` reflects the
    // WatchConnectivity link driven by T001 (unpaired/unreachable → not
    // connected); `hrLastValue` + `heartRateReceivedAt` gate the `awaiting`
    // vs `value` UI transitions. When the connection state is not `.reachable`
    // we always render the disconnected state regardless of the last value.
    @State private var currentHeartRate: Double?
    @State private var heartRateReceivedAt: Date?
    @State private var hrConnectionState: WatchConnectionState = .unsupported
    // MY-1245: track custom-numeric-keyboard visibility so the FAB can retreat
    // when the input keyboard is on screen — prevents the FAB from covering
    // input rows / row controls. `UITextField.inputView` (WorkoutNumericKeyboard)
    // still fires the standard `UIResponder.keyboardWill{Show,Hide}Notification`
    // through iOS input system, so a simple notification observer is enough
    // and avoids adding a bespoke publisher inside the input view.
    @State private var isKeyboardVisible = false
    // MY-1446: VoiceOver focus moves to snackbar when it appears (replicates
    // the old SnackbarModifier's @AccessibilityFocusState behavior).
    @AccessibilityFocusState private var isBottomSnackbarFocused: Bool
    @AccessibilityFocusState private var isTopSnackbarFocused: Bool
    // MY-1446 P0-1: buffered rest-completed presentation. Extracted to a
    // testable presenter so lifecycle (buffer capture, controller clear survival,
    // undo interruption, fresh 2s countdown) can be verified deterministically.
    @State private var restCompletedPresenter = RestCompletedPresenter()
    #if !os(macOS)
    @State private var sessionManager: (any WorkoutSessionManaging)?
    #endif
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @State private var displayMode: WorkoutDisplayMode = .tiled
    @State private var focusedSetID: PersistentIdentifier?

    private var legacyLayoutLarge: Bool { displayMode == .focus }
    @State private var startTime = Date()
    let source: WorkoutStartSource

    init(
        source: WorkoutStartSource = .blank,
    ) {
        self.source = source
    }

    private func requestFinish() {
        showingFinishAlert = true
    }







    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactInfoBand
                workoutContent
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                workoutInputDock
            }
            .navigationTitle(String(localized: "训练中", comment: "Active workout navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "放弃", comment: "Discard workout toolbar button"), role: .destructive) { showingDiscardAlert = true }
                        .frame(minWidth: 44, minHeight: 44)
                }
                ToolbarItem(placement: .principal) {
                    Picker(String(localized: "训练模式", comment: "Workout display mode"), selection: $displayMode) {
                        Label(String(localized: "平铺", comment: "Tiled workout mode"), systemImage: "square.grid.2x2").tag(WorkoutDisplayMode.tiled)
                        Label(String(localized: "专注", comment: "Focus workout mode"), systemImage: "circle.dotted").tag(WorkoutDisplayMode.focus)
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: displayMode)
                    .frame(maxWidth: 180)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(String(localized: "重量单位", comment: "Weight unit"), selection: $weightUnit) {
                            Text("kg").tag(WeightUnit.kg)
                            Text("lb").tag(WeightUnit.lb)
                        }
                        Button(String(localized: "动作大纲", comment: "Exercise outline"), systemImage: "list.bullet") { isSidebarReordering = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(String(localized: "训练选项", comment: "Workout options"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成", comment: "Finish workout"), action: requestFinish)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .sheet(isPresented: $showingExercisePicker) { ExercisePickerView { exercises in exercises.forEach(addExercise) } }
            .sheet(isPresented: $isSidebarReordering) { outlineSheet }
            .sheet(item: $exerciseToReplace) { target in ExercisePickerView { target.exercise = $0 } }
            .sheet(item: $exerciseToSubstitute) { target in
                ExerciseSubstituteSheet(
                    state: substituteSheetState,
                    onSelect: { applySubstitute($0, to: target) },
                    onManualSelect: {
                        signalStore?.updateLatestAccepted(kind: AICallSite.substitute.kind, accepted: false)
                        substituteManualFallback = target
                        exerciseToSubstitute = nil
                    }
                )
            }
            .sheet(item: $substituteManualFallback) { target in ExercisePickerView(initialMuscleGroup: target.exercise?.muscleGroup) { target.exercise = $0 } }
            .alert(String(localized: "完成训练？", comment: "Finish workout alert title"), isPresented: $showingFinishAlert) {
                Button(String(localized: "完成", comment: "Confirm finish")) { finishWorkout() }
                Button(String(localized: "取消", comment: "Cancel"), role: .cancel) {}
            } message: { Text(String(localized: "未完成的组将标记为完成并保存训练。", comment: "Finish workout message")) }
            .alert(String(localized: "放弃训练？", comment: "Discard workout alert title"), isPresented: $showingDiscardAlert) {
                Button(String(localized: "放弃", comment: "Confirm discard"), role: .destructive) { discardWorkout() }
                Button(String(localized: "继续训练", comment: "Continue workout"), role: .cancel) {}
            } message: { Text(String(localized: "训练数据将不会保存。", comment: "Discard workout message")) }
            .onAppear {
                displayMode = WorkoutDisplayMode.resolveInitialMode(
                    storedRawValue: UserDefaults.standard.string(forKey: "activeWorkoutDisplayMode"),
                    flightFocusDefault: flightStore?.effectiveValue(for: WorkoutFlight.focusModeDefault) ?? false
                )
                setupWorkout()
            }
            .onChange(of: displayMode) { _, mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "activeWorkoutDisplayMode")
            }
            .task(id: restTimer.restEndDate) { await restTimer.handleTimerTask() }
            .onChange(of: restTimer.phase) { _, phase in
                if phase == .completed {
                    HapticManager.trigger(.restCompleted)
                    restCompletedPresenter.captureCompleted()
                    if displayMode == .focus, let workout {
                        focusedSetID = WorkoutDualModeEngine.nextIncompleteStep(after: focusedSetID, in: workout)?.set.persistentModelID
                    }
                } else if phase == .resting, restCompletedPresenter.isBuffered {
                    restCompletedPresenter.dismiss()
                }
            }
            .onChange(of: bottomSnackbarSlot) { _, newSlot in
                if newSlot == .rest {
                    restCompletedPresenter.markVisible()
                } else {
                    restCompletedPresenter.markOccluded()
                }
            }
            .onAppear {
                restCompletedPresenter.onDismiss = { [restTimer] in
                    restTimer.dismissCompleted()
                }
                if bottomSnackbarSlot == .rest {
                    restCompletedPresenter.markVisible()
                }
                restCompletedPresenter.resume()
            }
            .onDisappear {
                restCompletedPresenter.cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                // swiftlint:disable:next silent_model_save
                try? modelContext.save()
            }
            #if !os(macOS)
            .task { await observeHeartRate() }
            .task { await observeHeartRateConnection() }
            .task { await monitorHeartRateStaleness() }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            #endif
        }
    }

    @ViewBuilder
    private var workoutContent: some View {
        let exercises = sortedExercises
        if exercises.isEmpty {
            VStack(spacing: 16) {
                ContentUnavailableView(String(localized: "添加第一个动作", comment: "Empty workout"), systemImage: "figure.strengthtraining.traditional", description: Text(String(localized: "选择动作开始训练", comment: "Empty workout description")))
                Button { showingExercisePicker = true } label: {
                    Label(String(localized: "添加动作", comment: "Add exercise"), systemImage: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(minWidth: 180, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayMode == .focus, let workout {
            ActiveWorkoutFocusStageView(
                workout: workout,
                focusedSetID: $focusedSetID,
                selectedExerciseID: $selectedExerciseID,
                restTimer: restTimer,
                weightUnit: weightUnit,
                heartRateText: focusHeartRateText,
                onAddExercise: { showingExercisePicker = true },
                onAddSet: addFocusedSet,
                onSubstitute: { if let target = selectedWorkoutExercise { beginSubstituteFlow(for: target) } },
                onReplace: { exerciseToReplace = selectedWorkoutExercise },
                onOutline: { isSidebarReordering = true },
                onFinish: requestFinish
            )
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(exercises) { workoutExercise in
                        ActiveExerciseSection(
                            workoutExercise: workoutExercise,
                            onSetCompleted: { completedSet in
                                restTimer.startRest(duration: completedSet.restDuration ?? completedSet.setType.defaultRestDuration)
                                TelemetryService.shared.trackNonisolated(.setCompleted(exerciseName: TelemetryHelpers.exerciseIdentifier(workoutExercise.exercise)))
                            },
                            onSetDeleted: { TelemetryService.shared.trackNonisolated(.setDeleted) },
                            onReplace: { exerciseToReplace = workoutExercise },
                            onSubstitute: { beginSubstituteFlow(for: workoutExercise) },
                            onDelete: { deleteExercise(workoutExercise) },
                            undoController: undoController
                        )
                            .id(workoutExercise.persistentModelID)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.defaultMinListRowHeight, 1)
                .accessibilityIdentifier("workout_exercise_list")
                .onChange(of: selectedExerciseID) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } } }
            }
        }
    }

    @ViewBuilder
    private var workoutInputDock: some View {
        if displayMode == .focus {
            EmptyView()
        } else if isKeyboardVisible {
            if undoController.pending != nil || restTimer.phase == .resting || restCompletedPresenter.isBuffered {
                HStack(spacing: 10) {
                    if undoController.pending != nil {
                        undoStatusButton
                    } else if restTimer.phase == .resting {
                        restSnackbarContent
                    } else {
                        restCompletedButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(.regularMaterial)
            }
        } else {
            HStack(spacing: 10) {
            if undoController.pending != nil {
                Button { undoController.undo(using: modelContext) } label: { Label(String(localized: "已删除组 · 撤销", comment: "Undo deletion"), systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 50)
            } else if restTimer.phase == .resting {
                restSnackbarContent
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else if restCompletedPresenter.isBuffered {
                Button { restCompletedPresenter.dismiss(); restTimer.dismissCompleted() } label: { Label(String(localized: "休息结束", comment: "Rest complete"), systemImage: "checkmark.circle.fill") }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                Button { showingExercisePicker = true } label: { Label(String(localized: "添加动作", comment: "Add exercise"), systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            if undoController.pending != nil || restTimer.phase == .resting || restCompletedPresenter.isBuffered {
                Button { showingExercisePicker = true } label: { Image(systemName: "plus") }
                    .frame(width: 48, height: 48)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(String(localized: "添加动作", comment: "Add exercise"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.regularMaterial)
        }
    }

    private var undoStatusButton: some View {
        Button { undoController.undo(using: modelContext) } label: {
            Label(String(localized: "已删除组 · 撤销", comment: "Undo deletion"), systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var restCompletedButton: some View {
        Button { restCompletedPresenter.dismiss(); restTimer.dismissCompleted() } label: {
            Label(String(localized: "休息结束", comment: "Rest complete"), systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var outlineSheet: some View {
        NavigationStack {
            List {
                ForEach(sortedExercises) { exercise in
                    Button { selectedExerciseID = exercise.persistentModelID; isSidebarReordering = false } label: {
                        HStack { Text(exercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise")); Spacer(); Text("\((exercise.sets ?? []).filter(\.isCompleted).count)/\((exercise.sets ?? []).count)").monospacedDigit().foregroundStyle(.secondary) }
                    }
                }
                .onMove(perform: moveExercises)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "动作大纲", comment: "Exercise outline"))
            .toolbar { EditButton() }
        }
        .presentationDetents([.medium, .large])
    }



    // MARK: - Compact info band (MY-1262, default mode)

    /// Single-row information band that replaces the standalone timer + stats
    /// cards in default mode. Presents duration, heart rate (iOS), completed/
    /// total sets with a compact progress ring, and total volume in a
    /// horizontal layout at body scale. Sits above the scrolling exercise list
    /// (parent `VStack`) so it stays visible while sets scroll. Each metric is
    /// its own VoiceOver element with a localized label/value pair.
    @ViewBuilder
    private var compactInfoBand: some View {
        let volumeKg = totalVolumeKg
        let displayVolume = weightUnit == .lb ? volumeKg * 2.20462 : volumeKg
        let volumeText = Int(displayVolume).formatted()
        HStack(alignment: .center, spacing: 12) {
            compactDurationItem
            #if !os(macOS)
            compactHeartRateItem
            #endif
            Spacer(minLength: 0)
            exerciseSheetTrigger
            compactSetsItem
            compactVolumeItem(volumeText: volumeText, unit: weightUnit.rawValue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(minHeight: legacyLayoutLarge ? 56 : 48)
        .background(workoutSecondaryGroupedBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(workoutSeparator).frame(height: 1)
        }
    }

    private var compactDurationItem: some View {
        TimelineView(.periodic(from: startTime, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let totalSeconds = Int(elapsed)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            let timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "timer")
                    .font(legacyLayoutLarge ? .body : .subheadline)
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
                Text(timeString)
                    .font(Font.system(legacyLayoutLarge ? .title3 : .subheadline, design: .default).monospacedDigit())
                    .foregroundStyle(Color.primary)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.22),
                        value: timeString
                    )
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "训练时长", comment: "Workout duration a11y label"))
            .accessibilityValue(Text(timeString))
            .frame(minHeight: 24, alignment: .center)
        }
    }

    #if !os(macOS)
    private var compactHeartRateItem: some View {
        let state = heartRateDisplayState
        let bpmText = HeartRateFormatter.displayText(state)
        return HStack(alignment: .center, spacing: 4) {
            Image(systemName: "heart.fill")
                .font(legacyLayoutLarge ? .body : .subheadline)
                .foregroundStyle(theme.danger)
                .accessibilityHidden(true)
            Text(bpmText)
                .font(Font.system(legacyLayoutLarge ? .title3 : .subheadline, design: .default).monospacedDigit())
                .foregroundStyle(Color.primary)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.22),
                    value: bpmText
                )
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "心率", comment: "Heart rate a11y label"))
        .accessibilityValue(HeartRateFormatter.accessibilityText(state))
        .frame(minHeight: 24, alignment: .center)
    }
    #endif

    private var compactSetsItem: some View {
        let progress = totalSetCount == 0
            ? 0.0
            : Double(completedSetCount) / Double(totalSetCount)
        let clamped = min(1, max(0, progress))
        return HStack(alignment: .center, spacing: 6) {
            ZStack {
                Circle()
                    .stroke(workoutSeparator, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
            Text("\(completedSetCount)/\(totalSetCount)")
                .font(Font.system(legacyLayoutLarge ? .title3 : .subheadline, design: .default).monospacedDigit())
                .foregroundStyle(Color.primary)
                .contentTransition(
                    reduceMotion ? .opacity : .numericText(countsDown: false)
                )
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.22),
                    value: completedSetCount
                )
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "组数进度", comment: "Session set progress a11y label"))
        .accessibilityValue(String(
            localized: "已完成 \(completedSetCount) / \(totalSetCount) 组",
            comment: "Session set progress a11y value"
        ))
        .frame(minHeight: 24, alignment: .center)
    }

    private func compactVolumeItem(volumeText: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(volumeText)
                .font(Font.system(legacyLayoutLarge ? .title3 : .subheadline, design: .default).monospacedDigit())
                .foregroundStyle(Color.primary)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.22),
                    value: volumeText
                )
                .layoutPriority(1)
            Text(unit)
                .font(legacyLayoutLarge ? .subheadline : .caption)
                .foregroundStyle(Color.secondary)
        }

        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "总容量", comment: "Session total volume a11y label"))
        .accessibilityValue(Text("\(volumeText) \(unit)"))
        .frame(minHeight: 24, alignment: .center)
    }

    private var exerciseSheetTrigger: some View {
        Button {
            isSidebarReordering = true
        } label: {
            Image(systemName: "list.bullet")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .accessibilityIdentifier("workout_exercise_sheet_trigger")
        .accessibilityLabel(
            String(
                localized: "workout.sidebar.title",
                defaultValue: "Exercises",
                comment: "Open exercise navigation and reorder sheet"
            )
        )
    }

    // MARK: - Subviews

    private var totalSetCount: Int {
        (workout?.exercises ?? []).reduce(0) { $0 + ($1.sets?.count ?? 0) }
    }

    private var completedSetCount: Int {
        (workout?.exercises ?? []).reduce(0) { partial, exercise in
            partial + (exercise.sets ?? []).filter(\.isCompleted).count
        }
    }

    // MARK: - Bottom snackbar arbitration (MY-1420)

    /// Which of the two competing bottom snackbars is showing right now.
    /// MY-1446 P0-1: uses the presenter's buffer so that even after the
    /// controller independently resets phase→.idle, the slot still resolves
    /// to `.rest` while the presentation is pending.
    private var bottomSnackbarSlot: BottomSnackbarSlot {
        let effectivePhase: RestPhase = restCompletedPresenter.isBuffered ? .completed : restTimer.phase
        return undoController.slot(restPhase: effectivePhase)
    }

    // MARK: - Envelope content for ZStack-based stable height (MY-1446 P0-1)

    /// Delegates to `ActiveWorkoutSnackbarLayout.undoEnvelope` — the production
    /// helper exercised by tests. Both message text and sizing reference share
    /// `.lineLimit(2)`, so the envelope height is deterministic at any Dynamic
    /// Type size.
    @ViewBuilder
    private var undoSnackbarEnvelope: some View {
        let overrideMessage: String? = nil
        ActiveWorkoutSnackbarLayout.undoEnvelope(
            message: undoController.pending?.message ?? overrideMessage,
            undoTitle: String(
                localized: "active_workout.set_delete.undo_action",
                defaultValue: "Undo",
                comment: "Undo a set deletion snackbar action"
            ),
            messageColor: Color.primary,
            undoColor: Color.accentColor,
            theme: theme,
            undoAccessibilityLabel: String(
                localized: "active_workout.set_delete.undo_action_a11y",
                defaultValue: "Undo deletion",
                comment: "Undo set deletion a11y label"
            ),
            restEndDate: restTimer.phase == .resting ? restTimer.restEndDate : nil,
            largeMode: legacyLayoutLarge,
            onUndo: {
                undoController.undo(using: modelContext)
            }
        )
    }

    /// Always renders the rest layout structure regardless of rest timer state.
    /// Delegates to `ActiveWorkoutSnackbarLayout.restEnvelope` (the production
    /// helper exercised by tests) so the hidden sizing reference guarantees
    /// stable height across completed/resting variants.
    @ViewBuilder
    private var restSnackbarEnvelope: some View {
        ActiveWorkoutSnackbarLayout.restEnvelope(
            skipTitle: String(localized: "跳过", comment: "Skip rest button visible title"),
            neutralBackground: workoutTertiaryFill,
            skipBackground: theme.interactiveAccent,
            theme: theme,
            largeMode: legacyLayoutLarge
        ) {
            restSnackbarContent
        }
    }

    @ViewBuilder
    private var restSnackbarContent: some View {
        if restCompletedPresenter.isBuffered {
            Button {
                restCompletedPresenter.dismiss()
                restTimer.dismissCompleted()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text(String(localized: "休息结束", comment: "Rest completed banner text"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "休息结束", comment: "Rest completed a11y label"))
            .accessibilityHint(String(localized: "点击关闭", comment: "Dismiss rest completed banner a11y hint"))
        } else if restTimer.phase == .resting, let restEnd = restTimer.restEndDate {
            let totalDuration = restTimer.restTotalDuration ?? (0)
            let totalSeconds = max(1, Int(totalDuration))
            TimelineView(.periodic(from: startTime, by: 1)) { context in
                let remaining = max(0, Int(restEnd.timeIntervalSince(context.date)))
                HStack(spacing: 8) {
                    ActiveWorkoutRestStatus(
                        remaining: remaining, totalSeconds: totalSeconds, theme: theme
                    )
                    Spacer(minLength: 0)
                    restAdjustButtons
                }
            }
        }
    }

    // MY-1446 P0-2: production now calls the same helper exercised by tests.
    private var restAdjustButtons: some View {
        ActiveWorkoutSnackbarLayout.restTimerButtons(
            skipTitle: String(localized: "跳过", comment: "Skip rest button visible title"),
            neutralBackground: workoutTertiaryFill,
            skipBackground: theme.interactiveAccent,
            theme: theme,
            minus10AccessibilityLabel: String(localized: "缩短十秒", comment: "Subtract 10 seconds a11y label"),
            plus10AccessibilityLabel: String(localized: "延长十秒", comment: "Add 10 seconds a11y label"),
            skipAccessibilityLabel: String(localized: "跳过休息", comment: "Skip rest a11y label"),
            onMinus10: { restTimer.adjustRest(by: -10) },
            onPlus10: { restTimer.adjustRest(by: 10) },
            onSkip: { restTimer.skipRest() }
        )
    }



    private var sortedExercises: [WorkoutExercise] {
        (workout?.exercises ?? []).sorted { $0.order < $1.order }
    }

    private var selectedWorkoutExercise: WorkoutExercise? {
        sortedExercises.first { $0.persistentModelID == selectedExerciseID } ?? sortedExercises.first
    }

    private var focusHeartRateText: String {
        #if !os(macOS)
        return HeartRateFormatter.displayText(heartRateDisplayState)
        #else
        return String(localized: "等待采样", comment: "Heart rate unavailable on macOS")
        #endif
    }

    private func addFocusedSet() {
        guard let target = selectedWorkoutExercise else { return }
        _ = ActiveExerciseSection.insertAppendedMainSet(in: target, using: modelContext)
    }

    private func moveSidebarExercise(
        source: Int,
        destination: Int,
        exercises: [WorkoutExercise],
        selectExercise: @escaping (WorkoutExercise) -> Void
    ) {
        guard exercises.indices.contains(source) else { return }
        let movedExercise = exercises[source]
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.15)
                : .spring(response: 0.28, dampingFraction: 0.82)
        ) {
            moveExercises(from: IndexSet(integer: source), to: destination)
        }
        HapticManager.trigger(.setCompleted)
        selectExercise(movedExercise)
    }

    private func moveExerciseUp(at index: Int) {
        guard index > 0 else { return }
        moveSidebarExercise(
            source: index,
            destination: index - 1,
            exercises: sortedExercises,
            selectExercise: { _ in }
        )
    }

    private func moveExerciseDown(at index: Int) {
        guard index < sortedExercises.count - 1 else { return }
        moveSidebarExercise(
            source: index,
            destination: index + 2,
            exercises: sortedExercises,
            selectExercise: { _ in }
        )
    }

    private var totalVolumeKg: Double {
        (workout?.exercises ?? []).reduce(0.0) { $0 + $1.workingVolume }
    }

    // MARK: - Actions

    #if !os(macOS)
    /// MY-1283: derive the three-state display via the pure
    /// `HeartRateStateResolver`. Kept as a thin adapter so the view code
    /// reads naturally and the resolver stays unit-testable in isolation.
    private var heartRateDisplayState: HeartRateDisplayState {
        HeartRateStateResolver.resolve(
            connection: hrConnectionState,
            lastValue: currentHeartRate,
            lastTimestamp: heartRateReceivedAt,
            now: Date(),
            freshnessLimit: HeartRateStateResolver.defaultFreshnessLimit
        )
    }

    /// Consume the realtime Watch → iPhone HR stream exposed by T001
    /// (`PhoneWorkoutSessionManager.observeLiveWorkoutHeartRate()`) instead
    /// of passively polling the local HealthKit store. Falls back to the
    /// pre-existing local anchored query for platforms / managers that
    /// don't implement the live stream (default protocol impl returns a
    /// finished stream — the `for await` loop simply exits then, and the
    /// legacy passive read below fills in).
    ///
    /// Freshness is stamped from the payload's own `timestamp`, NOT from
    /// receipt-time (`Date()`): a payload that was queued while the phone
    /// was asleep must not render as "just now" the instant it arrives.
    /// The resolver's freshness window is compared against this sample-time
    /// stamp, so an old payload immediately resolves to `.awaiting`.
    private func observeHeartRate() async {
        // Live Watch → iPhone stream (T001). Never logs the bpm value (§I).
        // Per-payload logic lives in HeartRateStreamAdapter.applyLivePayload
        // so unit tests can drive the exact same code path with a real
        // AsyncStream — any regression to receipt-time stamping breaks
        // HeartRateStreamAdapterTests.consumeLiveHeartRate_stampsFromPayloadTimestamp.
        if let manager = sessionManager {
            let stream = await manager.observeLiveWorkoutHeartRate()
            await HeartRateStreamAdapter.consumeLiveHeartRate(
                stream,
                setValue: { currentHeartRate = $0 },
                setTimestamp: { heartRateReceivedAt = $0 }
            )
        }
        // Legacy passive-read fallback (kept so macOS-adjacent builds and
        // NoopWorkoutSessionManager runs still surface any value the local
        // store already holds). Realtime path is preferred; this only runs
        // if the live stream finished immediately.
        for await dataPoint in healthKitService.observeHeartRate() {
            guard dataPoint.startDate.timeIntervalSinceNow > -120 else { continue }
            currentHeartRate = dataPoint.value
            heartRateReceivedAt = dataPoint.startDate
        }
    }

    /// Track the T001 WatchConnectivity connection-state stream so the UI
    /// can drop to the honest "not connected" state the moment the Watch
    /// link goes away (unpaired, unreachable, or unsupported).
    ///
    /// Per-state logic lives in `HeartRateStreamAdapter.applyConnectionState`
    /// so tests can exercise the exact same code path — including the
    /// mandatory clear of `currentHeartRate` + `heartRateReceivedAt` on
    /// any non-`.reachable` transition. Post-drop UX contract: reconnect
    /// always enters `.awaiting` until the first post-reconnect sample.
    private func observeHeartRateConnection() async {
        guard let manager = sessionManager else { return }
        let stream = await manager.observeConnectionState()
        await HeartRateStreamAdapter.consumeConnectionState(
            stream,
            setConnection: { hrConnectionState = $0 },
            setValue: { currentHeartRate = $0 },
            setTimestamp: { heartRateReceivedAt = $0 }
        )
    }

    private func monitorHeartRateStaleness() async {
        // Realtime stream should surface staleness faster than the historic
        // 120 s window. `heartRateDisplayState` already down-grades to
        // `.awaiting` after the resolver's freshness window; here we just
        // clear the held value+timestamp so stale numbers can't linger in
        // memory across a long silence. Preserves ADR-0010: no fabricated
        // values. Compared against the sample-time timestamp (not receipt
        // time) so a stalled stream can't hide behind a fresh receipt clock.
        let freshnessLimit = HeartRateStateResolver.defaultFreshnessLimit
        let checkInterval: Duration = .seconds(5)
        while !Task.isCancelled {
            try? await Task.sleep(for: checkInterval)
            if let receivedAt = heartRateReceivedAt,
               Date().timeIntervalSince(receivedAt) > freshnessLimit {
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
        selectedExerciseID = result.workout.exercises?.min(by: { $0.order < $1.order })?.persistentModelID
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
        Task { try? await manager.startSession() }
        #endif
    }

    private func addExercise(_ exercise: Exercise) {
        guard let workout else { return }
        let order = workout.exercises?.count ?? 0
        let workoutExercise = WorkoutExercise(order: order, exercise: exercise)
        workoutExercise.workout = workout
        modelContext.insert(workoutExercise)

        Self.prefillHistory(in: workoutExercise, workout: workout, using: modelContext)
        selectedExerciseID = workoutExercise.persistentModelID

        TelemetryService.shared.trackNonisolated(
            .exerciseAdded(name: TelemetryHelpers.exerciseIdentifier(exercise))
        )
    }

    /// Copy values into fresh, incomplete rows; historical model identities stay untouched.
    @discardableResult
    static func prefillHistory(
        in workoutExercise: WorkoutExercise,
        workout: Workout,
        using context: ModelContext
    ) -> [ExerciseSet] {
        guard let first = PreviousSetLookup.previousMainSet(
            currentWorkout: workout, exercise: workoutExercise.exercise, mainSetIndex: 0, in: context
        ) else {
            let set = ExerciseSet(order: 0, weight: 0, reps: 0)
            set.workoutExercise = workoutExercise
            context.insert(set)
            return [set]
        }
        // The lookup identifies the latest session. Copy its complete ordered set tree,
        // including drop sets, rather than repeatedly fetching once per row.
        let previous = (first.workoutExercise?.sets ?? [first]).sorted { $0.order < $1.order }
        return previous.enumerated().map { index, prior in
            let set = ExerciseSet(
                order: index, weight: prior.weight, reps: prior.reps, setType: prior.setType,
                restDuration: prior.restDuration, isUnilateral: prior.isUnilateral,
                weightRight: prior.weightRight
            )
            set.workoutExercise = workoutExercise
            context.insert(set)
            return set
        }
    }

    // MARK: - Substitute flow (T013)

    private func beginSubstituteFlow(for workoutExercise: WorkoutExercise) {
        substituteLoadTask?.cancel()
        guard let exercise = workoutExercise.exercise else {
            substituteSheetState = .error(
                message: String(
                    localized: "active_workout.substitute.error_no_candidates",
                    defaultValue: "No matching alternatives found.",
                    comment: "Substitute sheet: no usable AI candidates fallback message"
                )
            )
            exerciseToSubstitute = workoutExercise
            return
        }

        let request = SubstituteRequest(
            name: exercise.localizedName,
            muscleGroup: exercise.muscleGroup,
            equipment: exercise.equipment
        )
        let currentPresetId = exercise.presetId
        let expectedMuscleGroup = exercise.muscleGroup
        let muscleGroupDisplay = exercise.muscleGroup.localizedName

        substituteSheetState = .loading
        exerciseToSubstitute = workoutExercise

        let container = modelContext.container
        substituteLoadTask = Task {
            let outcome = await loadSubstitutes(
                request: request,
                excludingPresetId: currentPresetId,
                expectedMuscleGroup: expectedMuscleGroup,
                muscleGroupDisplay: muscleGroupDisplay,
                container: container
            )
            guard !Task.isCancelled else { return }
            substituteSheetState = outcome
        }
    }

    private func applySubstitute(
        _ recommendation: ExerciseSubstituteSheet.Recommendation,
        to workoutExercise: WorkoutExercise
    ) {
        substituteLoadTask?.cancel()
        substituteLoadTask = nil
        guard let replacement = ExerciseSeeder.findByPresetId(
            recommendation.id,
            context: modelContext
        ) else {
            logger.info("substitute apply skipped: reason=missingLocalExercise")
            // Missing local exercise still means the user tried to apply the AI
            // suggestion — mark accepted=true so the signal reflects intent, not
            // whether the seeder found the row.
            signalStore?.updateLatestAccepted(kind: AICallSite.substitute.kind, accepted: true)
            exerciseToSubstitute = nil
            return
        }
        workoutExercise.exercise = replacement
        HapticManager.trigger(.exerciseAdded)
        signalStore?.updateLatestAccepted(kind: AICallSite.substitute.kind, accepted: true)
        exerciseToSubstitute = nil
    }

    private func loadSubstitutes(
        request: SubstituteRequest,
        excludingPresetId: String?,
        expectedMuscleGroup: MuscleGroup,
        muscleGroupDisplay: String,
        container: ModelContainer
    ) async -> ExerciseSubstituteSheet.ViewState {
        let messages = SubstitutePromptBuilder.build(for: request)
        let apiKey = try? KeychainHelper().load(service: AISettingsSection.apiKeyKeychainService)
        let router = AIRouterFactory.makeDefault(zhipuAPIKey: apiKey, signalSink: signalStore)

        let response: ChatResponse
        do {
            let selectedModel = UserDefaults.standard.string(forKey: "aiModel")
            response = try await router.execute(kind: AICallSite.substitute.kind, messages: messages, model: selectedModel)
        } catch {
            logger.info("substitute AI request failed: category=\(Self.errorCategory(error))")
            return .error(
                message: String(
                    localized: "active_workout.substitute.error_generic",
                    defaultValue: "Couldn't get smart suggestions right now.",
                    comment: "Substitute sheet: generic AI/network error fallback message"
                )
            )
        }

        let suggestions: [SubstituteSuggestion]
        do {
            suggestions = try SubstituteSuggestion.parse(
                from: response.content,
                excluding: excludingPresetId
            )
        } catch {
            logger.info("substitute parse failed: category=invalidJSON")
            return .error(
                message: String(
                    localized: "active_workout.substitute.error_generic",
                    defaultValue: "Couldn't get smart suggestions right now.",
                    comment: "Substitute sheet: generic AI/network error fallback message"
                )
            )
        }

        let recommendations = await resolveRecommendations(
            suggestions: suggestions,
            expectedMuscleGroup: expectedMuscleGroup,
            muscleGroupDisplay: muscleGroupDisplay,
            container: container
        )
        logger.info("substitute resolved: candidates=\(recommendations.count)")

        guard !recommendations.isEmpty else {
            return .error(
                message: String(
                    localized: "active_workout.substitute.error_no_candidates",
                    defaultValue: "No matching alternatives found.",
                    comment: "Substitute sheet: no usable AI candidates fallback message"
                )
            )
        }
        return .results(recommendations)
    }

    private func resolveRecommendations(
        suggestions: [SubstituteSuggestion],
        expectedMuscleGroup: MuscleGroup,
        muscleGroupDisplay: String,
        container: ModelContainer
    ) async -> [ExerciseSubstituteSheet.Recommendation] {
        await Task.detached { @Sendable in
            let context = ModelContext(container)
            var results: [ExerciseSubstituteSheet.Recommendation] = []
            var seenIds: Set<String> = []
            for suggestion in suggestions {
                guard !seenIds.contains(suggestion.exerciseId) else { continue }
                guard let exercise = ExerciseSeeder.findByPresetId(
                    suggestion.exerciseId,
                    context: context
                ) else { continue }
                guard SubstituteRecommendationFilter.acceptsSameMuscleGroup(
                    exerciseMuscleGroup: exercise.muscleGroup,
                    expected: expectedMuscleGroup
                ) else {
                    logger.info(
                        "substitute rejected: reason=muscleGroupMismatch presetId=\(suggestion.exerciseId, privacy: .public)"
                    )
                    continue
                }
                seenIds.insert(suggestion.exerciseId)
                results.append(
                    ExerciseSubstituteSheet.Recommendation(
                        id: suggestion.exerciseId,
                        name: exercise.localizedName,
                        muscleGroup: muscleGroupDisplay,
                        reason: suggestion.reason
                    )
                )
            }
            return results
        }.value
    }

    private static func errorCategory(_ error: Error) -> String {
        if let aiError = error as? AIServiceError {
            switch aiError {
            case .noProviderAvailable: return "noProviderAvailable"
            case .networkError: return "networkError"
            case .httpError(let statusCode): return "httpError(\(statusCode))"
            case .missingAPIKey: return "missingAPIKey"
            case .responseParsingFailed: return "responseParsingFailed"
            case .streamingInterrupted: return "streamingInterrupted"
            }
        }
        if error is SubstituteParseError { return "invalidJSON" }
        return "unknown"
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var exercises = (workout?.exercises ?? []).sorted { $0.order < $1.order }
        guard !source.isEmpty, source.allSatisfy({ exercises.indices.contains($0) }),
              (0...exercises.count).contains(destination) else { return }
        exercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in exercises.enumerated() {
            exercise.order = index
        }
    }

    private func deleteExercise(_ workoutExercise: WorkoutExercise) {
        // MY-1420: a set-delete undo pending against *this* exercise must go
        // with it. Otherwise "delete a set → delete the whole exercise inside
        // the 5s window → tap 撤销" would reinsert `ExerciseSet` rows against a
        // deleted `WorkoutExercise`. `SetDeletionUndoController.undo` also
        // refuses a dead parent, but clearing here is what makes the snackbar
        // disappear along with the rows it refers to.
        undoController.clearIfPending(for: workoutExercise)
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
        // MY-1420: an undo pending at finish would try to reinsert into a
        // workout that is already closed out — close the window instead.
        undoController.clear()
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
        // MY-1420: same reasoning as `finishWorkout` — the workout the
        // snapshot belongs to is about to be deleted.
        undoController.clear()
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

// MARK: - Heart Rate Display State (MY-1283)

/// Three-state model for the active-workout heart-rate display. Replaces the
/// ambiguous single "nil → --" placeholder (ADR-0010 Consequences: users
/// without an Apple Watch must not see a value or imply one).
///
/// - `disconnected`: No paired / reachable Watch. UI shows an explicit
///   "not connected" prompt; never renders a numeric value or the raw `--`.
/// - `awaiting`: Watch session is active but no HR sample has arrived yet.
///   UI shows a neutral waiting glyph so the user can tell we're online but
///   haven't received data.
/// - `value(bpm)`: Live BPM from the Watch's `HKLiveWorkoutBuilder` stream.
enum HeartRateDisplayState: Equatable {
    case disconnected
    case awaiting
    case value(Double)
}

// MARK: - Heart Rate State Resolver (MY-1283)

/// Pure resolver that maps (connection, last sample) → three-state display.
///
/// Extracted from `ActiveWorkoutView` so both invariants can be exercised
/// under unit tests without spinning up SwiftUI @State:
///
/// - **Reconnect enters `.awaiting`**: when the WatchConnectivity link
///   drops the view MUST clear the held value+timestamp so a reconnect
///   cannot re-render the pre-drop BPM as fresh. The view enforces the
///   clear on the state transition; the resolver enforces the
///   guard-clause: a non-`.reachable` connection always resolves to
///   `.disconnected` regardless of held values.
/// - **Freshness stamped from payload time, not receipt time**: callers
///   pass the payload's own `timestamp` as `lastTimestamp` (never
///   `Date()`) so a delayed sample can't inherit a fresh clock. The
///   resolver compares `now - lastTimestamp` against `freshnessLimit`;
///   any sample older than the window resolves to `.awaiting`.
enum HeartRateStateResolver {
    /// Freshness window used by the live-workout HR display. Chosen to
    /// surface a dropped realtime stream faster than the historical 120 s
    /// passive-read window while still tolerating a normal HR sampling
    /// cadence (~5 s intervals).
    static let defaultFreshnessLimit: TimeInterval = 20

    /// - Parameters:
    ///   - connection: current `WatchConnectivity` link state.
    ///   - lastValue: last received BPM (nil if none received or cleared
    ///     by a link-drop).
    ///   - lastTimestamp: sample time reported by the payload (NOT the
    ///     receipt clock). Nil mirrors `lastValue == nil`.
    ///   - now: current wall clock; injected for testability.
    ///   - freshnessLimit: max age (seconds) a value may still render as
    ///     `.value`. Older or absent samples fall through to `.awaiting`.
    static func resolve(
        connection: WatchConnectionState,
        lastValue: Double?,
        lastTimestamp: Date?,
        now: Date,
        freshnessLimit: TimeInterval = defaultFreshnessLimit
    ) -> HeartRateDisplayState {
        guard connection == .reachable else {
            return .disconnected
        }
        guard let value = lastValue, let timestamp = lastTimestamp else {
            return .awaiting
        }
        let age = now.timeIntervalSince(timestamp)
        // A future-dated timestamp (clock skew) or a fresh sample both
        // render as `.value`; anything older than the window falls to
        // `.awaiting`.
        guard age <= freshnessLimit else {
            return .awaiting
        }
        return .value(value)
    }
}

// MARK: - Heart Rate Stream Adapter (MY-1283)

/// Testable adapter that owns the *production* per-item logic used by
/// `ActiveWorkoutView.observeHeartRate()` and
/// `ActiveWorkoutView.observeHeartRateConnection()`. Both view methods
/// delegate to the two static consumers below — so any regression in the
/// production write behavior (e.g. re-introducing receipt-time `Date()`
/// stamping, or forgetting to clear the held value on disconnect) breaks
/// the tests that drive these consumers with real `AsyncStream`s.
///
/// The adapter deliberately has NO reference to SwiftUI: mutations are
/// applied via `@MainActor` closures so the view can plug in `@State`
/// setters, and tests can plug in a tiny in-memory holder. This keeps
/// the adapter Sendable-safe under Swift 6 strict concurrency while
/// exercising the same per-item statements the view runs in production.
///
/// Privacy: consumers never log the bpm value (§I). Only stream lifetime
/// / transition events would be loggable, and none are added here.
@MainActor
enum HeartRateStreamAdapter {

    /// Per-payload mutation used by `observeHeartRate`.
    ///
    /// Freshness MUST be stamped from `payload.timestamp` (the sample time
    /// reported by the Watch). Never `Date()` — a delayed payload must not
    /// inherit a fresh receipt clock. Regression guard: if a future edit
    /// switches this back to receipt-time, the corresponding test fails
    /// deterministically.
    static func applyLivePayload(
        _ payload: LiveHeartRatePayload,
        setValue: (Double?) -> Void,
        setTimestamp: (Date?) -> Void
    ) {
        setValue(payload.bpm)
        setTimestamp(payload.timestamp)
    }

    /// Drives a `LiveHeartRatePayload` stream to completion, applying each
    /// payload via `applyLivePayload`. Called from `observeHeartRate()`
    /// with the view's `@State` setters; called from tests with a small
    /// captured-state holder.
    static func consumeLiveHeartRate(
        _ stream: AsyncStream<LiveHeartRatePayload>,
        setValue: @MainActor @escaping (Double?) -> Void,
        setTimestamp: @MainActor @escaping (Date?) -> Void
    ) async {
        for await payload in stream {
            applyLivePayload(payload, setValue: setValue, setTimestamp: setTimestamp)
        }
    }

    /// Per-state mutation used by `observeHeartRateConnection`.
    ///
    /// On every non-`.reachable` transition we MUST clear the held BPM +
    /// timestamp; otherwise a reconnect would render the pre-drop BPM as
    /// fresh until a new sample arrived. Regression guard: dropping the
    /// clear breaks the corresponding disconnect→reconnect test.
    static func applyConnectionState(
        _ state: WatchConnectionState,
        setConnection: (WatchConnectionState) -> Void,
        setValue: (Double?) -> Void,
        setTimestamp: (Date?) -> Void
    ) {
        setConnection(state)
        if state != .reachable {
            setValue(nil)
            setTimestamp(nil)
        }
    }

    /// Drives a `WatchConnectionState` stream to completion, applying each
    /// state via `applyConnectionState`.
    static func consumeConnectionState(
        _ stream: AsyncStream<WatchConnectionState>,
        setConnection: @MainActor @escaping (WatchConnectionState) -> Void,
        setValue: @MainActor @escaping (Double?) -> Void,
        setTimestamp: @MainActor @escaping (Date?) -> Void
    ) async {
        for await state in stream {
            applyConnectionState(
                state,
                setConnection: setConnection,
                setValue: setValue,
                setTimestamp: setTimestamp
            )
        }
    }
}

enum HeartRateFormatter {
    /// Compact numeric / status text for the info-band and header.
    static func displayText(_ state: HeartRateDisplayState) -> String {
        switch state {
        case .disconnected:
            return String(
                localized: "active_workout.heart_rate.disconnected",
                defaultValue: "No Watch",
                comment: "Active workout HR compact display when Watch not connected"
            )
        case .awaiting:
            return String(
                localized: "active_workout.heart_rate.awaiting",
                defaultValue: "…",
                comment: "Active workout HR compact display waiting for first sample"
            )
        case .value(let bpm):
            return "\(Int(bpm))"
        }
    }

    /// VoiceOver value string. Uses the existing "N 次每分钟" a11y phrasing for
    /// the value case (unchanged) and dedicated localized prompts for the
    /// disconnected / awaiting states so screen-reader users get the same
    /// honest three-state signal as sighted users.
    static func accessibilityText(_ state: HeartRateDisplayState) -> String {
        switch state {
        case .disconnected:
            return String(
                localized: "active_workout.heart_rate.disconnected_a11y",
                defaultValue: "Apple Watch not connected",
                comment: "VoiceOver: no Apple Watch connected during workout"
            )
        case .awaiting:
            return String(
                localized: "active_workout.heart_rate.awaiting_a11y",
                defaultValue: "Waiting for heart rate",
                comment: "VoiceOver: connected but no HR sample yet"
            )
        case .value(let bpm):
            let intBPM = Int(bpm)
            return String(
                localized: "\(intBPM) 次每分钟",
                comment: "Heart rate a11y value with full unit"
            )
        }
    }
}

private struct FABButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.9 : 1.0))
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.6),
                value: configuration.isPressed
            )
    }
}

// MY-1088: preview wrapper. Seeds the `activeWorkoutLargeMode` @AppStorage
// key BEFORE `ActiveWorkoutView` initializes, so its own @AppStorage read
// picks up the seeded value and the Large Mode preview drives the same
// toolbar/render path as production instead of a synthetic environment.
private struct ActiveWorkoutPreview: View {
    init(largeMode: Bool) {
        UserDefaults.standard.set(largeMode ? WorkoutDisplayMode.focus.rawValue : WorkoutDisplayMode.tiled.rawValue, forKey: "activeWorkoutDisplayMode")
    }
    var body: some View {
        ActiveWorkoutView()
            .modelContainer(try! ModelContainerConfiguration.makeTestContainer()) // swiftlint:disable:this force_try
            .designThemePreview()
    }
}

#Preview("Normal Mode") {
    ActiveWorkoutPreview(largeMode: false)
}

#Preview("Large Mode") {
    ActiveWorkoutPreview(largeMode: true)
}