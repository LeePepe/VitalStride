// swiftlint:disable no_hardcoded_chinese
// Pre-existing `no_hardcoded_chinese` literals (alerts, a11y strings, summary
// line) predate the shared i18n cleanup and stay silenced at file scope until
// that migrates them to Localizable.xcstrings (matches DataView.swift).
import AIService
import DesignKit
import HealthKitService
import os
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
import VitalUI
#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveWorkout")

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if !os(macOS)
    @Environment(\.healthKitService) private var healthKitService
    #endif
    // Spec 019 Stage 3c (T017/T018): sink for the substitute request's
    // `RoutingSignal`, and the retro-write target for `accepted` after the
    // user applies or cancels a suggestion.
    @Environment(\.routingSignalStore) private var signalStore
    @State private var workout: Workout?
    @State private var showingExercisePicker = false
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
            VStack(spacing: 0) {
                // MY-1262: default mode collapses the standalone timer and stats
                // cards into a single ~48pt compact info band. Large Mode keeps
                // its dual-card layout so its accessibility presentation stays
                // intact.
                if largeMode {
                    workoutTimer
                    sessionStatsCard
                } else {
                    compactInfoBand
                }
                // MY-1446: when the keyboard is visible, the snackbar renders
                // inline between the header and the list (not as an overlay)
                // so it never covers the compact info band or gets clipped.
                // Uses the tested `topLayout` helper with separate undo/rest
                // envelope builders (same sizing-reference approach as
                // bottomSafeAreaContent ZStack) so slot transitions do not
                // cause list jump.
                if isKeyboardVisible {
                    ActiveWorkoutSnackbarLayout.topLayout(
                        snackbarSlot: bottomSnackbarSlot,
                        undoContent: { undoSnackbarEnvelope },
                        restContent: { restSnackbarEnvelope }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityFocused($isTopSnackbarFocused)
                }
                exerciseList
            }
            // MY-1446: unified bottom safe area — FAB above, snackbar below.
            // Uses VStack so non-overlap is guaranteed by construction. The
            // snackbar is fully within the safe area (never clipped by the
            // screen edge). Replaces the old overlay-based `.snackbar()`
            // modifier + offset workaround that caused touch-blocking and
            // top-edge overlap. The list's scroll inset adjusts smoothly via
            // animation when the snackbar appears/disappears.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
                        snackbarSlot: bottomSnackbarSlot,
                        undoContent: { undoSnackbarEnvelope },
                        restContent: { restSnackbarEnvelope },
                        fab: {
                            HStack {
                                Spacer()
                                ActiveWorkoutFABContainer.body(snackbarSlot: bottomSnackbarSlot) {
                                    addExerciseButton
                                }
                            }
                        }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityFocused($isBottomSnackbarFocused)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
            .animation(.easeInOut(duration: 0.2), value: bottomSnackbarSlot)
            .navigationTitle(String(localized: "训练中", comment: "Active workout navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        String(localized: "放弃", comment: "Discard workout toolbar button"),
                        role: .destructive
                    ) {
                        showingDiscardAlert = true
                    }
                }
                // MY-1353: Reorder affordance. EditButton drives the existing
                // List `.onMove` → moveExercises(from:to:) → WorkoutExercise.order.
                // Only render when there is more than one exercise to reorder.
                ToolbarItem(placement: .topBarTrailing) {
                    if (workout?.exercises?.count ?? 0) > 1 {
                        EditButton()
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
                                localized: "active_workout_toggle_normal_text_size",
                                defaultValue: "Switch to normal text size",
                                comment: "Active workout toggle: switch back to normal text size"
                            )
                            : String(
                                localized: "active_workout_toggle_large_text_size",
                                defaultValue: "Switch to large text size",
                                comment: "Active workout toggle: switch to large text size"
                            )
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "结束训练", comment: "Finish workout toolbar button")) {
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
            .sheet(item: $exerciseToSubstitute) { workoutExercise in
                ExerciseSubstituteSheet(
                    state: substituteSheetState,
                    onSelect: { recommendation in
                        applySubstitute(recommendation, to: workoutExercise)
                    },
                    onManualSelect: {
                        // T015: hand off from the AI substitute sheet to the
                        // manual `ExercisePickerView` fallback with the current
                        // exercise's muscle group preselected. Dismiss the
                        // AI sheet first, then present the picker on the next
                        // runloop tick so SwiftUI can finish the dismiss
                        // transition before starting a new presentation.
                        //
                        // Spec 019 Stage 3c (T018): user rejected the AI
                        // suggestions and switched to manual — mark the
                        // latest substitute signal accepted=false.
                        signalStore?.updateLatestAccepted(
                            kind: AICallSite.substitute.kind,
                            accepted: false
                        )
                        let target = workoutExercise
                        exerciseToSubstitute = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            substituteManualFallback = target
                        }
                    }
                )
            }
            .sheet(item: $substituteManualFallback) { workoutExercise in
                ExercisePickerView(
                    initialMuscleGroup: workoutExercise.exercise?.muscleGroup
                ) { newExercise in
                    workoutExercise.exercise = newExercise
                    HapticManager.trigger(.exerciseAdded)
                }
            }
            .alert(
                String(localized: "完成训练？", comment: "Finish workout alert title"),
                isPresented: $showingFinishAlert
            ) {
                Button(String(localized: "完成", comment: "Confirm finish workout button")) {
                    finishWorkout()
                }
                Button(
                    String(localized: "取消", comment: "Cancel finish workout button"),
                    role: .cancel
                ) {}
            } message: {
                Text(String(localized: "训练将被保存到历史记录", comment: "Finish workout alert message"))
            }
            .alert(
                String(localized: "放弃训练？", comment: "Discard workout alert title"),
                isPresented: $showingDiscardAlert
            ) {
                Button(
                    String(localized: "放弃", comment: "Confirm discard workout button"),
                    role: .destructive
                ) {
                    discardWorkout()
                }
                Button(
                    String(localized: "继续训练", comment: "Cancel discard workout button"),
                    role: .cancel
                ) {}
            } message: {
                Text(String(localized: "训练数据将不会保存", comment: "Discard workout alert message"))
            }
            .onAppear { setupWorkout() }
            .task(id: restTimer.restEndDate) {
                await restTimer.handleTimerTask()
            }
            .onChange(of: restTimer.phase) { _, newPhase in
                if newPhase == .completed {
                    HapticManager.trigger(.restCompleted)
                    // MY-1446 P0-1: buffer the completion in the presenter so
                    // the view layer manages presentation independently of the
                    // controller's own auto-clear sleep.
                    restCompletedPresenter.captureCompleted()
                } else if newPhase == .resting {
                    // MY-1446 P0-5: a new rest started — clear any stale buffered
                    // completion from the previous timer so it cannot reappear.
                    if restCompletedPresenter.isBuffered {
                        restCompletedPresenter.dismiss()
                    }
                }
            }
            // MY-1446: keep the presenter's slot visibility in sync and wire dismiss.
            .onChange(of: bottomSnackbarSlot) { _, newSlot in
                restCompletedPresenter.slotIsVisible = (newSlot == .rest)
                // MY-1446: move VoiceOver focus to snackbar when it appears
                // (replicates old SnackbarModifier's @AccessibilityFocusState).
                // Clear both bindings on .none; set mutually exclusively otherwise.
                switch newSlot {
                case .none:
                    isBottomSnackbarFocused = false
                    isTopSnackbarFocused = false
                case .undo, .rest:
                    if isKeyboardVisible {
                        isBottomSnackbarFocused = false
                        isTopSnackbarFocused = true
                    } else {
                        isTopSnackbarFocused = false
                        isBottomSnackbarFocused = true
                    }
                }
            }
            // MY-1446: migrate VoiceOver focus when keyboard visibility changes
            // while a snackbar is active. The snackbar moves between bottom and
            // top positions; without this, the focused container is removed and
            // the new one never receives focus.
            .onChange(of: isKeyboardVisible) { _, keyboardNowVisible in
                guard bottomSnackbarSlot != .none else { return }
                if keyboardNowVisible {
                    isBottomSnackbarFocused = false
                    isTopSnackbarFocused = true
                } else {
                    isTopSnackbarFocused = false
                    isBottomSnackbarFocused = true
                }
            }
            .onAppear {
                restCompletedPresenter.onDismiss = { [restTimer] in
                    restTimer.dismissCompleted()
                }
                restCompletedPresenter.slotIsVisible = (bottomSnackbarSlot == .rest)
                // MY-1446: restart countdown for any buffered completion that
                // survived a prior cancel() during disappear — prevents permanent
                // rest-completed display after navigate away and back.
                restCompletedPresenter.resume()
            }
            .onDisappear {
                // MY-1446 P0-1: cancel the presenter's countdown task to prevent
                // leaked polling loops when the view exits while slot is hidden.
                // Preserves isBuffered so resume() on reappear restarts the countdown.
                restCompletedPresenter.cancel()
            }
            // MY-1420: the deleted row took VoiceOver focus with it, and the
            // undo snackbar is deliberately non-modal (it must not block the
            // list), so an announcement is the only way a screen-reader user
            // learns the delete happened and is reversible. Keyed on the
            // announcement's identity, not its text — two identical deletions
            // in a row produce the same words and would otherwise announce once.
            .onChange(of: undoController.lastAnnouncement) { _, announcement in
                guard let announcement else { return }
                AccessibilityNotification.Announcement(announcement.message).post()
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
            .task { await observeHeartRateConnection() }
            .task { await monitorHeartRateStaleness() }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in
                isKeyboardVisible = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                isKeyboardVisible = false
            }
            #endif
        }
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
        HStack(spacing: 12) {
            compactDurationItem
            #if !os(macOS)
            compactHeartRateItem
            #endif
            Spacer(minLength: 0)
            compactSetsItem
            compactVolumeItem(volumeText: volumeText, unit: weightUnit.rawValue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(theme.neutrals.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.neutrals.border).frame(height: 1)
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
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)
                Text(timeString)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "训练时长", comment: "Workout duration a11y label"))
            .accessibilityValue(Text(timeString))
        }
    }

    #if !os(macOS)
    private var compactHeartRateItem: some View {
        let state = heartRateDisplayState
        let bpmText = HeartRateFormatter.displayText(state)
        return HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.subheadline)
                .foregroundStyle(theme.danger)
                .accessibilityHidden(true)
            Text(bpmText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.neutrals.text1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "心率", comment: "Heart rate a11y label"))
        .accessibilityValue(HeartRateFormatter.accessibilityText(state))
    }
    #endif

    private var compactSetsItem: some View {
        let progress = totalSetCount == 0
            ? 0.0
            : Double(completedSetCount) / Double(totalSetCount)
        let clamped = min(1, max(0, progress))
        return HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(theme.neutrals.border, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        theme.primary.primary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
            Text("\(completedSetCount)/\(totalSetCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.neutrals.text1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "组数进度", comment: "Session set progress a11y label"))
        .accessibilityValue(String(
            localized: "已完成 \(completedSetCount) / \(totalSetCount) 组",
            comment: "Session set progress a11y value"
        ))
    }

    private func compactVolumeItem(volumeText: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(volumeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.neutrals.text1)
            Text(unit)
                .font(.caption)
                .foregroundStyle(theme.neutrals.text3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "总容量", comment: "Session total volume a11y label"))
        .accessibilityValue(Text("\(volumeText) \(unit)"))
    }

    // MARK: - Subviews

    // MY-1082: only elapsed-time formatting stays inside the 1 Hz periodic
    // closure. Exercise/set counts and total volume are derived from
    // observable workout/set data and re-render only when that data changes,
    // not on every timer tick.
    @ViewBuilder
    private var workoutTimer: some View {
        let summaryText = summaryLine
        ViewThatFits(in: .horizontal) {
            HStack {
                timerLabel
                elapsedTimeText
                #if !os(macOS)
                heartRateLabel
                #endif
                Spacer()
                Text(summaryText)
                    .font(summaryFont)
                    .foregroundStyle(theme.neutrals.text2)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    timerLabel
                    elapsedTimeText
                    #if !os(macOS)
                    heartRateLabel
                    #endif
                    Spacer()
                }
                Text(summaryText)
                    .font(summaryFont)
                    .foregroundStyle(theme.neutrals.text2)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, largeMode ? 16 : 8)
        .background(theme.neutrals.card)
    }

    // MARK: - Session stats (ActiveWorkoutPrototype top)

    /// Live session summary: set-completion ring + total-volume big number +
    /// per-exercise volume sparkline. Everything is derived from the observable
    /// workout/set graph (no new @State, no per-tick work) so it re-renders only
    /// when the training data itself changes — the same MY-1082 contract the
    /// timer bar follows. Hidden until the workout has at least one set so the
    /// empty-workout state stays clean.
    @ViewBuilder
    private var sessionStatsCard: some View {
        if totalSetCount > 0 {
            let displayVolume = weightUnit == .lb ? totalVolumeKg * 2.20462 : totalVolumeKg
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    RingGauge(
                        value: totalSetCount == 0 ? 0 : Double(completedSetCount) / Double(totalSetCount),
                        size: 56,
                        stroke: 6
                    )
                    .accessibilityLabel(String(localized: "组数进度", comment: "Session set progress a11y label"))
                    .accessibilityValue(String(
                        localized: "已完成 \(completedSetCount) / \(totalSetCount) 组",
                        comment: "Session set progress a11y value"
                    ))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "组数进度", comment: "Session set progress label"))
                            .font(TypeScale.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.neutrals.text2)
                        Text("\(completedSetCount) / \(totalSetCount)")
                            .font(TypeScale.title.monospacedDigit())
                            .foregroundStyle(theme.neutrals.text1)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "总容量", comment: "Session total volume label"))
                            .font(TypeScale.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.neutrals.text2)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(Int(displayVolume).formatted())
                                .font(TypeScale.display)
                                .foregroundStyle(theme.neutrals.text1)
                            Text(weightUnit.rawValue)
                                .font(TypeScale.meta)
                                .foregroundStyle(theme.neutrals.text3)
                        }
                    }
                }

                if volumeSeries.count > 1 {
                    Sparkline(data: volumeSeries, color: theme.primary.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(theme.neutrals.card)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.neutrals.border).frame(height: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var totalSetCount: Int {
        (workout?.exercises ?? []).reduce(0) { $0 + ($1.sets?.count ?? 0) }
    }

    private var completedSetCount: Int {
        (workout?.exercises ?? []).reduce(0) { partial, exercise in
            partial + (exercise.sets ?? []).filter(\.isCompleted).count
        }
    }

    /// Per-exercise working-volume series driving the session sparkline. Ordered
    /// by the exercise `order` so the trend reads left-to-right in the same
    /// sequence the list shows. Purely derived from the observable graph.
    private var volumeSeries: [Double] {
        (workout?.exercises ?? [])
            .sorted { $0.order < $1.order }
            .map(\.workingVolume)
    }

    private var elapsedTimeText: some View {
        TimelineView(.periodic(from: startTime, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let totalSeconds = Int(elapsed)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            let timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            Text(timeString)
                .font(timerFont)
        }
    }

    private var summaryLine: String {
        let exerciseCount = workout?.exercises?.count ?? 0
        let setCount = workout?.exercises?
            .reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0
        let volumeKg = totalVolumeKg
        let displayVolume = weightUnit == .lb ? volumeKg * 2.20462 : volumeKg
        let volumeText = Int(displayVolume).formatted()
        return String(
            localized: "\(exerciseCount) 动作 · \(setCount) 组 · \(volumeText) \(weightUnit.rawValue)",
            comment: "Workout summary: exercise count, set count, total volume"
        )
    }

    private var timerLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .foregroundStyle(theme.neutrals.text2)
            Text(String(localized: "训练时长", comment: "Workout duration label"))
                .font(.subheadline)
                .foregroundStyle(theme.neutrals.text2)
        }
    }

    #if !os(macOS)
    private var heartRateLabel: some View {
        let state = heartRateDisplayState
        let bpmText = HeartRateFormatter.displayText(state)
        let unitText = String(localized: "次/分", comment: "Heart rate unit bpm")
        return HStack(spacing: 2) {
            Image(systemName: "heart.fill")
            Text(bpmText)
                .monospacedDigit()
            // Only render the "次/分" unit suffix alongside a real numeric
            // value — showing "未连接 次/分" would be nonsensical.
            if case .value = state {
                Text(unitText)
            }
        }
        .font(.subheadline)
        .foregroundStyle(theme.danger)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "心率", comment: "Heart rate a11y label"))
        .accessibilityValue(HeartRateFormatter.accessibilityText(state))
    }
    #endif

    // MARK: - Bottom snackbar arbitration (MY-1420)

    /// Which of the two competing bottom snackbars is showing right now.
    /// MY-1446 P0-1: uses the presenter's buffer so that even after the
    /// controller independently resets phase→.idle, the slot still resolves
    /// to `.rest` while the presentation is pending.
    private var bottomSnackbarSlot: BottomSnackbarSlot {
        let effectivePhase: RestPhase = restCompletedPresenter.isBuffered ? .completed : restTimer.phase
        return undoController.slot(restPhase: effectivePhase)
    }

    @ViewBuilder
    private var bottomSnackbarContent: some View {
        switch bottomSnackbarSlot {
        case .undo:
            undoSnackbarContent
        case .rest:
            restSnackbarContent
        case .none:
            EmptyView()
        }
    }

    // MARK: - Envelope content for ZStack-based stable height (MY-1446 P0-1)

    /// Delegates to `ActiveWorkoutSnackbarLayout.undoEnvelope` — the production
    /// helper exercised by tests. Both message text and sizing reference share
    /// `.lineLimit(2)`, so the envelope height is deterministic at any Dynamic
    /// Type size.
    @ViewBuilder
    private var undoSnackbarEnvelope: some View {
        ActiveWorkoutSnackbarLayout.undoEnvelope(
            message: undoController.pending?.message,
            undoTitle: String(
                localized: "active_workout.set_delete.undo_action",
                defaultValue: "Undo",
                comment: "Undo a set deletion snackbar action"
            ),
            messageColor: theme.neutrals.text1,
            undoColor: theme.primary.primary,
            undoAccessibilityLabel: String(
                localized: "active_workout.set_delete.undo_action_a11y",
                defaultValue: "Undo deletion",
                comment: "Undo set deletion a11y label"
            ),
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
            neutralBackground: theme.neutrals.inner,
            skipBackground: theme.primary.primary.opacity(0.15)
        ) {
            restSnackbarContent
        }
    }

    @ViewBuilder
    private var undoSnackbarContent: some View {
        if let pending = undoController.pending {
            HStack(spacing: Space.gap) {
                Text(pending.message)
                    .font(TypeScale.body)
                    .lineLimit(2)
                    .foregroundStyle(theme.neutrals.text1)
                Spacer()
                Button {
                    undoController.undo(using: modelContext)
                } label: {
                    Text(String(
                        localized: "active_workout.set_delete.undo_action",
                        defaultValue: "Undo",
                        comment: "Undo a set deletion snackbar action"
                    ))
                        .font(TypeScale.body.weight(.semibold))
                        .foregroundStyle(theme.primary.primary)
                        .frame(minWidth: Space.minTapTarget, minHeight: Space.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    localized: "active_workout.set_delete.undo_action_a11y",
                    defaultValue: "Undo deletion",
                    comment: "Undo set deletion a11y label"
                ))
            }
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
                        .foregroundStyle(theme.success)
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
                            .stroke(theme.neutrals.border, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(theme.primary.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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

    // MY-1446 P0-2: production now calls the same helper exercised by tests.
    private var restAdjustButtons: some View {
        ActiveWorkoutSnackbarLayout.restTimerButtons(
            skipTitle: String(localized: "跳过", comment: "Skip rest button visible title"),
            neutralBackground: theme.neutrals.inner,
            skipBackground: theme.primary.primary.opacity(0.15),
            minus10AccessibilityLabel: String(localized: "缩短十秒", comment: "Subtract 10 seconds a11y label"),
            plus10AccessibilityLabel: String(localized: "延长十秒", comment: "Add 10 seconds a11y label"),
            skipAccessibilityLabel: String(localized: "跳过休息", comment: "Skip rest a11y label"),
            onMinus10: { restTimer.adjustRest(by: -10) },
            onPlus10: { restTimer.adjustRest(by: 10) },
            onSkip: { restTimer.skipRest() }
        )
    }

    @ViewBuilder
    private var exerciseList: some View {
        let exercises = (workout?.exercises ?? []).sorted { $0.order < $1.order }
        if exercises.isEmpty {
            ContentUnavailableView(
                String(localized: "添加第一个动作", comment: "Empty active workout title"),
                systemImage: "figure.strengthtraining.traditional",
                description: Text(
                    String(
                        localized: "点击下方按钮选择训练动作",
                        comment: "Empty active workout description"
                    )
                )
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
                        onSubstitute: {
                            beginSubstituteFlow(for: workoutExercise)
                        },
                        onDelete: {
                            deleteExercise(workoutExercise)
                        },
                        undoController: undoController
                    )
                }
                .onMove { source, destination in
                    moveExercises(from: source, to: destination)
                }
                // MY-1245: FAB inset is now reserved by `safeAreaInset(edge:
                // .bottom)` in `body`, so a manual 72pt footer spacer is no
                // longer needed — it would double-count the reserved area.
            }
            // MY-877: plain list style + immediate keyboard dismissal on scroll
            // for compact, scannable in-workout entry. Reduce default row floor
            // so main SetRow targets ~36pt and SubSetRow targets ~28pt.
            .listStyle(.plain)
            // MY-1274 (P0): tighten the inter-exercise section gap in default
            // mode. SwiftUI's `.plain` List still applies a ~28pt system inset
            // between sections (gap A in the issue) which reads as "too big".
            // Large Mode keeps a 20pt cushion to match its intentionally
            // roomier accessibility layout; default drops to 8pt for a
            // "compact but not cramped" band-to-band rhythm.
            .listSectionSpacing(largeMode ? 20 : 8)
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
                .foregroundStyle(theme.primary.onPrimary)
                .frame(width: 60, height: 60)
                .background(Circle().fill(theme.primary.primary))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(FABButtonStyle())
        .accessibilityLabel(String(localized: "添加动作", comment: "Add exercise FAB a11y label"))
        .padding()
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

        let defaultSet = ExerciseSet(order: 0, weight: 0, reps: 0, setType: .working)
        defaultSet.workoutExercise = workoutExercise
        modelContext.insert(defaultSet)

        TelemetryService.shared.trackNonisolated(
            .exerciseAdded(name: TelemetryHelpers.exerciseIdentifier(exercise))
        )
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
            .designThemePreview()
    }
}

#Preview("Normal Mode") {
    ActiveWorkoutPreview(largeMode: false)
}

#Preview("Large Mode") {
    ActiveWorkoutPreview(largeMode: true)
}
