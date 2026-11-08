import SwiftData
import SwiftUI
import VitalModels

struct ActiveWorkoutFocusStageView: View {
    @Bindable var workout: Workout
    @Binding var focusedSetID: PersistentIdentifier?
    @Binding var selectedExerciseID: PersistentIdentifier?
    @Bindable var restTimer: RestTimerController
    let weightUnit: WeightUnit; let heartRateText: String
    let onAddExercise: () -> Void; let onAddSet: () -> Void; let onSubstitute: () -> Void; let onReplace: () -> Void; let onOutline: () -> Void; let onFinish: () -> Void
    private var step: FocusStep? { WorkoutDualModeEngine.syncCursor(selectedExerciseID: selectedExerciseID, selectedSetID: focusedSetID, in: workout) }
    var body: some View {
        let current = step; let mode: FocusStageMode = restTimer.phase == .resting ? .restRecovery : (current == nil ? .allCompleted : .activeSet); let palette = FocusAtmosphereTheme.resolve(muscleGroup: current?.exercise.exercise?.muscleGroup, stageMode: mode)
        ZStack { LinearGradient(colors: [palette.primaryTint.opacity(0.24), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea(); RadialGradient(colors: [palette.secondaryTint.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 300).ignoresSafeArea(); ScrollView { VStack(spacing: 18) { if let current { header(current); stage(current, palette: palette) } else { ContentUnavailableView(String(localized: "active_workout.focus.completed", defaultValue: "全部动作已完成", comment: "All workout sets completed"), systemImage: "checkmark.circle.fill"); Button(String(localized: "active_workout.finish", defaultValue: "完成训练", comment: "Finish workout"), action: onFinish).buttonStyle(.borderedProminent) } }.padding(16) } }
    }
    private func header(_ step: FocusStep) -> some View { VStack(spacing: 6) { Button(action: onOutline) { Text(String(localized: "动作 \(step.exerciseIndex + 1) / \(workout.exercises?.count ?? 0) ▾", comment: "Exercise position and outline trigger")).font(.subheadline.weight(.semibold)) }.buttonStyle(.bordered).clipShape(Capsule()); Text(step.exercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise")).font(.title.weight(.bold)); Text(String(localized: "第 \(step.mainSetNumber + 1) / \(step.totalSetsInExercise) 组", comment: "Set position")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) } }
    @ViewBuilder private func stage(_ step: FocusStep, palette: FocusAtmosphereTheme) -> some View { if restTimer.phase == .resting { recovery(step, palette: palette) } else { active(step, palette: palette) } }
    private func active(_ step: FocusStep, palette: FocusAtmosphereTheme) -> some View { VStack(spacing: 14) { reference(step, palette: palette); HStack(spacing: 12) { FocusModule(title: String(localized: "重量 · \(weightUnit.rawValue.uppercased())", comment: "Weight module"), value: step.set.weight, unit: weightUnit, field: .weight, step: step, palette: palette); FocusModule(title: String(localized: "次数 · REPS", comment: "Reps module"), value: Double(step.set.reps), unit: weightUnit, field: .reps, step: step, palette: palette) }; Button { step.set.isCompleted = true; restTimer.startRest(duration: step.set.restDuration ?? step.set.setType.defaultRestDuration) } label: { Label(String(localized: "active_workout.complete_set", defaultValue: "完成本组", comment: "Complete current set"), systemImage: "checkmark").font(.headline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 58) }.buttonStyle(.borderedProminent).tint(palette.primaryTint) } }
    private func reference(_ step: FocusStep, palette: FocusAtmosphereTheme) -> some View { Text(String(localized: "上次参考 · 点击数字可编辑", comment: "Previous reference hint")).font(.caption).foregroundStyle(palette.primaryTint).frame(maxWidth: .infinity, alignment: .center) }
    private func recovery(_ step: FocusStep, palette: FocusAtmosphereTheme) -> some View { VStack(spacing: 14) { TimelineView(.periodic(from: .now, by: 1)) { context in let total = max(1, restTimer.restTotalDuration ?? 1); let remaining = max(0, Int((restTimer.restEndDate ?? context.date).timeIntervalSince(context.date))); ZStack { Circle().stroke(palette.secondaryTint.opacity(0.18), lineWidth: 14); Circle().trim(from: 0, to: min(1, Double(remaining) / total)).stroke(LinearGradient(colors: [palette.primaryTint, palette.secondaryTint], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90)); VStack { Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).font(.system(size: 48, weight: .heavy, design: .rounded).monospacedDigit()); Text("♥ \(heartRateText)").font(.caption.monospacedDigit()) } }.frame(width: 210, height: 210) }; HStack { Button("−15s") { restTimer.adjustRest(by: -15) }; Button(String(localized: "跳过休息", comment: "Skip rest")) { restTimer.skipRest() }; Button("+15s") { restTimer.adjustRest(by: 15) } }.buttonStyle(.bordered); Button(String(localized: "active_workout.undo_set", defaultValue: "撤回上一组", comment: "Undo completion")) { step.set.isCompleted = false; restTimer.skipRest() }.buttonStyle(.plain) } }
}
private struct FocusModule: View {
    let title: String
    let value: Double
    let unit: WeightUnit
    let field: SetField
    let step: FocusStep
    let palette: FocusAtmosphereTheme
    private var displayValue: String {
        if value == 0 { return "0" }
        if field == .reps { return "\(Int(value))" }
        return WorkoutDualModeEngine.displayWeight(value, unit: unit).formatted(.number.precision(.fractionLength(0...1)))
    }
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(palette.primaryTint)
            Text(displayValue).font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
            HStack {
                Button(field == .reps ? "−1" : "−2.5") { FocusSetStepper.adjust(field == .reps ? .reps : .weight, by: -1, unit: unit, set: step.set) }
                Button(field == .reps ? "+1" : "+2.5") { FocusSetStepper.adjust(field == .reps ? .reps : .weight, by: 1, unit: unit, set: step.set) }
            }.buttonStyle(.bordered).tint(palette.primaryTint)
        }
        .frame(maxWidth: .infinity, minHeight: 190).padding(12)
        .background(palette.primaryTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.primaryTint.opacity(0.25), lineWidth: 1.5))
    }
}
