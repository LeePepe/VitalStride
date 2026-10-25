import DesignKit
import SwiftUI

struct CompactPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let firm: Bool
    init(firm: Bool = false) { self.firm = firm }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? (firm ? 0.96 : 0.98) : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

/// Layout study V2. One visual treatment, three compact information structures.
public struct CompactStudioView: View {
    @Environment(\.theme) private var theme
    @Bindable private var session: CompactSession
    @State private var picker = CompactPickerModel()
    private let layout: CompactLayout
    private let snapshot: Bool

    public init(session: CompactSession, layout: CompactLayout, snapshot: Bool = false, picker: CompactPickerModel? = nil) {
        self.session = session; self.layout = layout; self.snapshot = snapshot
        self._picker = State(initialValue: picker ?? CompactPickerModel())
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("9:41").monospacedDigit()
                Spacer()
                Text(studioText("demo.badge")).foregroundStyle(theme.neutrals.text2)
                Spacer()
                Image(systemName: "battery.100percent").accessibilityHidden(true)
            }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 20).frame(height: 28)
            if session.contentState != .populated {
                CompactStateView(state: session.contentState, retry: { session.contentState = .populated })
            } else if session.core.screen == .picker {
                CompactPickerView(session: session, model: picker, snapshot: snapshot)
            } else if session.core.isFinished {
                Spacer()
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(theme.success)
                Text(studioText("compact.finished")).font(.title2.bold())
                Text(studioText("demo.badge")).font(.caption).foregroundStyle(theme.neutrals.text2)
                Spacer()
                Button { session.core.isFinished = false } label: {
                    Text(studioText("compact.back")).frame(minWidth: 88, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                CompactWorkoutHeader(core: session.core)
                if layout == .rail {
                    CompactRailWorkout(session: session, snapshot: snapshot)
                        .overlay(alignment: .bottom) {
                            CompactSnackbar(session: session, snapshot: snapshot)
                                .padding(.horizontal, 12).padding(.bottom, 10)
                        }
                } else {
                    CompactWorkoutBody(session: session, layout: layout, snapshot: snapshot)
                    CompactStatusLine(session: session)
                }
                if session.core.editorField != nil { CompactKeyboard(session: session, glass: layout == .rail, snapshot: snapshot) }
                else if layout == .rail { railActions }
                else { workoutActions }
            }
            Capsule().fill(theme.neutrals.text1).frame(width: 120, height: 4)
                .padding(.top, 8).padding(.bottom, 8).accessibilityHidden(true)
        }
        .foregroundStyle(theme.neutrals.text1).background(theme.neutrals.bg)
        .overlay {
            if let overlay = session.overlay {
                CompactDrawer(session: session, picker: picker, kind: overlay, snapshot: snapshot)
            }
        }
    }
    private var railActions: some View {
        VStack(spacing: 0) {
            Button { session.navigation.jump(to: session.core.activeExerciseID, order: session.core.workoutIDs) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scope").accessibilityHidden(true)
                    Text(studioText("compact.actionTarget") + " · " + studioText("exercise.short.\(session.core.activeExerciseID)") + " · " + studioText("set.number") + " " + (session.selectedSetNumber.map(String.init) ?? "—"))
                    Spacer(minLength: 0)
                    Text(studioText("compact.locate"))
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.neutrals.text2)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(CompactPressStyle()).padding(.horizontal, 12)
            workoutActions.padding(.top, -8).padding(.bottom, 8)
        }.modifier(CompactGlassSurface(radius: 22, snapshot: snapshot))
            .padding(.horizontal, 8).padding(.top, 4)
    }
    private var workoutActions: some View {
        HStack(spacing: 8) {
            CompactTool(title: studioText("compact.more"), symbol: "ellipsis") { session.overlay = .more }
            CompactTool(title: studioText("compact.addSet"), symbol: "plus") { session.addSet() }
            Button { session.completeSelected() } label: {
                Label(layout == .rail ? compactSetActionTitle(session: session, editing: false) : studioText(session.selectedSet?.completed == true ? "set.uncomplete" : "compact.logSet"), systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(theme.primary.onPrimary).background(theme.primary.primary, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(CompactPressStyle()).disabled(session.selectedSet == nil)
        }.padding(.horizontal, 12).padding(.top, 8)
    }
}

private struct CompactWorkoutHeader: View {
    @Environment(\.theme) private var theme
    let core: StudioSession
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.down").accessibilityHidden(true)
                Text(studioText("workout.title")).font(.headline)
                Spacer()
                Text(studioText("compact.inProgress")).font(.caption).foregroundStyle(theme.neutrals.text2)
            }.frame(height: 40)
            HStack(spacing: 12) {
                Text("24:18").monospacedDigit()
                Text("\(core.completedCount)/\(core.totalCount) " + studioText("workout.setUnit")).monospacedDigit()
                Text(core.totalVolume.formatted(.number.precision(.fractionLength(0))) + " kg").monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "applewatch.slash").accessibilityLabel(studioText("workout.watchOffline"))
            }.font(.caption).foregroundStyle(theme.neutrals.text2).frame(height: 24)
        }.padding(.horizontal, 12).overlay(alignment: .bottom) { Divider() }
    }
}

private struct CompactWorkoutBody: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    let layout: CompactLayout
    let snapshot: Bool
    var body: some View {
        ScrollViewReader { proxy in
            CompactViewport(snapshot: snapshot) { sectionContent }
                .scrollIndicators(.hidden)
                .onChange(of: session.core.editorField != nil) { _, editing in
                    if editing { proxy.scrollTo(session.core.activeExerciseID, anchor: .top) }
                }
        }
    }
    @ViewBuilder private var sectionContent: some View {
        if layout == .matrix {
            ForEach(session.core.workoutIDs, id: \.self) { id in
                CompactMatrixSection(session: session, exerciseID: id).id(id)
            }
        } else {
            horizontalNavigation
            activeTable.id(session.core.activeExerciseID)
            HStack {
                Text(studioText("compact.plan")).font(.caption.weight(.semibold))
                Spacer()
                Text(studioText("compact.tapSwitch")).font(.caption)
            }.foregroundStyle(theme.neutrals.text2).padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
            ForEach(session.core.workoutIDs.filter { $0 != session.core.activeExerciseID }, id: \.self) { id in
                queueRow(id)
            }
        }
    }
    private var horizontalNavigation: some View {
        HStack(spacing: 0) {
            ForEach(Array(session.core.workoutIDs.enumerated()), id: \.element) { index, id in
                Button { session.select(exercise: id) } label: {
                    VStack(spacing: 3) {
                        Text("\(index + 1) · " + studioText("exercise.short.\(id)"))
                            .font(.caption.weight(session.core.activeExerciseID == id ? .bold : .regular)).lineLimit(1)
                        Rectangle().fill(session.core.activeExerciseID == id ? theme.primary.primary : .clear).frame(height: 2)
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).accessibilityAddTraits(session.core.activeExerciseID == id ? .isSelected : [])
            }
        }.padding(.horizontal, 12)
    }
    private var activeTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.core.activeExercise.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(session.core.activeSets.filter(\.completed).count)/\(session.core.activeSets.count)").font(.caption).monospacedDigit()
            }.padding(.horizontal, 12).frame(minHeight: 48)
            CompactTableHeader(narrow: layout == .rail)
            ForEach(Array(session.core.activeSets.enumerated()), id: \.element.id) { index, set in
                CompactSetRow(session: session, exerciseID: session.core.activeExerciseID, set: set, index: index, narrow: layout == .rail)
            }
            HStack(spacing: 4) {
                Image(systemName: "info.circle").accessibilityHidden(true)
                Text(studioText("compact.historyDemo"))
                Spacer()
            }.font(.caption2).foregroundStyle(theme.neutrals.text2).padding(.horizontal, 12).frame(minHeight: 32)
        }
    }
    private func queueRow(_ id: String) -> some View {
        Button { session.select(exercise: id) } label: {
            HStack(spacing: 12) {
                Text("\((session.core.workoutIDs.firstIndex(of: id) ?? 0) + 1)").font(.caption).foregroundStyle(theme.neutrals.text2).frame(width: 24)
                Text(studioText("exercise.\(id)")).font(.subheadline).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(session.core.setsByExercise[id]?.filter(\.completed).count ?? 0)/\(session.core.setsByExercise[id]?.count ?? 0)").font(.caption).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true)
            }.padding(.horizontal, 12).frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }
}

private struct CompactTableHeader: View {
    @Environment(\.theme) private var theme
    let narrow: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text(studioText("set.number")).frame(width: 44)
            if !narrow { Text(studioText("compact.previous")).frame(maxWidth: .infinity) }
            Text(studioText("set.weight") + " kg").frame(maxWidth: .infinity)
            Text(studioText("set.reps")).frame(width: 48)
            Text(studioText("compact.state")).frame(width: 44)
        }.font(.caption2).foregroundStyle(theme.neutrals.text2).padding(.horizontal, 12).frame(height: 28)
            .background(theme.neutrals.inner)
    }
}

struct CompactSetRow: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    let exerciseID: String
    let set: StudioSet
    let index: Int
    let narrow: Bool
    private var selected: Bool { session.core.activeExerciseID == exerciseID && session.selectedSetID == set.id }
    private var editing: Bool { selected && session.core.editorField != nil }
    var body: some View {
        HStack(spacing: 4) {
            Button { session.select(exercise: exerciseID, setID: set.id) } label: {
                VStack(spacing: 1) {
                    Text(String(index + 1)).font(.subheadline.weight(.semibold))
                    Text(studioText((editing ? session.currentKind : set.kind) == "warmup" ? "compact.warmupShort" : "compact.workingShort")).font(.caption2)
                }.frame(width: 44, height: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(studioText("set.number") + " \(index + 1)")
            if !narrow {
                Text(set.kind == "warmup" ? "40 × 12" : "60 × 10")
                    .font(.caption).foregroundStyle(theme.neutrals.text2).monospacedDigit().frame(maxWidth: .infinity)
            }
            HStack(spacing: 2) {
                weightCell(right: false)
                if editing ? session.core.editorIsSplit : set.weightRight != nil { weightCell(right: true) }
            }.frame(maxWidth: .infinity)
            Button { if session.select(exercise: exerciseID, setID: set.id) { session.edit("reps") } } label: {
                Text(editing ? session.core.editorRepsText : String(set.reps)).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                .frame(width: 48, height: 48)
                .background(editing ? theme.primary.primarySubtle : .clear, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .overlay { if editing { RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(theme.primary.primaryText, lineWidth: 1) } }
            }.buttonStyle(CompactPressStyle()).accessibilityLabel(studioText("editor.reps"))
            Button { if session.select(exercise: exerciseID, setID: set.id) { session.completeSelected() } } label: {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .font(.system(size: 20))
                    .foregroundStyle(set.completed ? Color.black : theme.neutrals.text2, theme.success)
                    .frame(width: 44, height: 48)
            }.buttonStyle(CompactPressStyle(firm: true)).accessibilityLabel(studioText(set.completed ? "set.uncomplete" : "set.complete"))
        }.padding(.horizontal, 12).padding(.vertical, 2)
            .background(theme.neutrals.card)
            .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func weightCell(right: Bool) -> some View {
        let split = editing ? session.core.editorIsSplit : set.weightRight != nil
        let value = editing ? (right ? session.core.editorRightWeightText : session.core.editorWeightText) :
            (right ? (set.weightRight ?? 0) : set.weight).formatted(.number.precision(.fractionLength(0...2)))
        return Button {
            if session.select(exercise: exerciseID, setID: set.id) { session.edit(right ? "weightRight" : "weight") }
        } label: {
            VStack(spacing: 0) {
                if split { Text(studioText(right ? "weight.right" : "weight.left")).font(.system(size: 10)).foregroundStyle(theme.neutrals.text2) }
                Text(value).font(.system(split ? .subheadline : .body, design: .rounded, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.75).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 48).frame(minWidth: 44)
                .background(editing ? theme.primary.primarySubtle : .clear, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .overlay { if editing { RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(theme.primary.primaryText, lineWidth: 1) } }
        }.buttonStyle(CompactPressStyle()).accessibilityLabel(studioText(split ? (right ? "weight.right" : "weight.left") : "editor.weight"))
            .accessibilityValue(value + " kg")
    }
}

private struct CompactMatrixSection: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    let exerciseID: String
    private var sets: [StudioSet] { session.core.setsByExercise[exerciseID] ?? [] }
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(studioText("exercise.\(exerciseID)")).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(sets.filter(\.completed).count)/\(sets.count)").font(.caption).foregroundStyle(theme.neutrals.text2)
            }.frame(minHeight: 32)
            // One lazy section container in the runtime parent; bounded eager rows here.
            ForEach(0..<((sets.count + 3) / 4), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(Array(sets.dropFirst(row * 4).prefix(4).enumerated()), id: \.element.id) { offset, set in
                        tile(set, index: row * 4 + offset)
                    }
                    if min(4, sets.count - row * 4) < 4 {
                        ForEach(0..<(4 - min(4, sets.count - row * 4)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }.padding(.horizontal, 12).padding(.bottom, 10).overlay(alignment: .bottom) { Divider() }
    }
    private func tile(_ set: StudioSet, index: Int) -> some View {
        let selected = session.core.activeExerciseID == exerciseID && session.selectedSetID == set.id
        let editing = selected && session.core.editorField != nil
        let weight = editing ? session.core.editorWeightText : set.weight.formatted(.number.precision(.fractionLength(0...2)))
        let reps = editing ? session.core.editorRepsText : String(set.reps)
        return Button { if session.select(exercise: exerciseID, setID: set.id) { session.edit("weight") } } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(String(index + 1)).font(.caption2)
                    Spacer(minLength: 0)
                    if set.completed { Image(systemName: "checkmark").foregroundStyle(theme.success).accessibilityHidden(true) }
                    else if selected { Image(systemName: "pencil").accessibilityHidden(true) }
                }
                Text(weight + " kg").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("× " + reps).font(.caption).foregroundStyle(theme.neutrals.text2).monospacedDigit()
            }.padding(8).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? theme.primary.primaryBorder : .clear))
        }.buttonStyle(.plain).accessibilityLabel(studioText("set.number") + " \(index + 1) " + studioText(set.completed ? "set.doneShort" : "editor.weight"))
    }
}

private struct CompactStatusLine: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    var body: some View {
        HStack(spacing: 8) {
            if session.core.deletedSet != nil {
                Text(studioText("compact.deleted")).font(.caption)
                Spacer()
                Button { session.core.undoDelete() } label: {
                    Text(studioText("action.undo")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
            } else if let end = session.core.restEnd {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                    Label(String(format: "%d:%02d", seconds / 60, seconds % 60), systemImage: "timer").monospacedDigit()
                }
                Spacer()
                Button { session.core.adjustRest(-10) } label: {
                    Text(studioText("rest.minusShort")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                Button { session.core.adjustRest(10) } label: {
                    Text(studioText("rest.plusShort")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                Button { session.core.restEnd = nil } label: {
                    Text(studioText("rest.skip")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
            } else {
                Text(session.notice ?? studioText("compact.selected") + " " + (session.selectedSetNumber.map(String.init) ?? "—"))
                Spacer(minLength: 0)
                Text(studioText("compact.rpe") + " " + (session.currentRPE.map(String.init) ?? "—"))
            }
        }.font(.caption).buttonStyle(.plain).foregroundStyle(theme.primary.primaryText)
            .padding(.horizontal, 12).frame(height: 44).background(theme.neutrals.inner)
            .overlay(alignment: .top) { Divider() }
    }
}

private struct CompactTool: View {
    @Environment(\.theme) private var theme
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15)).accessibilityHidden(true)
                Text(title).font(.caption2)
            }.frame(minWidth: 48, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(theme.neutrals.text1).accessibilityLabel(title)
    }
}

private struct CompactKeyboard: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    var glass = false
    var snapshot = false
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if session.isEditingEquipmentDefault {
                    Button { session.selectEquipmentDefaultValue() } label: {
                        HStack {
                            Text(studioText("weight.defaultTotal")).font(.caption)
                            Spacer(minLength: 4)
                            Text(session.equipmentDefaultText.isEmpty ? "—" : session.equipmentDefaultText)
                                .font(.title3.weight(.semibold)).monospacedDigit()
                                .background(session.defaultSelectAll ? theme.primary.primaryBorder.opacity(0.4) : .clear)
                            Text("kg").font(.caption)
                        }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
                            .background(theme.primary.primarySubtle, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).accessibilityLabel(studioText("weight.defaultTotal"))
                        .accessibilityValue(session.equipmentDefaultText + " kg")
                    StudioIconButton(symbol: "xmark", label: studioText("action.cancel")) { session.cancelEquipmentDefault() }
                } else {
                    field("weight", value: session.core.editorWeightText)
                    if session.core.editorIsSplit { field("weightRight", value: session.core.editorRightWeightText) }
                    field("reps", value: session.core.editorRepsText)
                    StudioIconButton(symbol: "keyboard.chevron.compact.down", label: studioText("keyboard.saveClose")) { session.save() }
                        .disabled(!session.core.editorCanCommit)
                }
            }
            HStack(spacing: 4) {
                if session.isEditingEquipmentDefault {
                    Text(studioText("weight.defaultScope")).font(.system(size: 12)).foregroundStyle(theme.neutrals.text2)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    auxiliary("compact.previous", symbol: "clock.arrow.circlepath") { session.core.usePreviousEditorValues() }
                    auxiliary(session.core.editorIsSplit ? "weight.split" : "weight.total", symbol: "arrow.left.arrow.right") { session.accessory = .weight }
                    auxiliary("compact.rpe", symbol: "gauge.with.dots.needle.50percent") { session.accessory = .rpe }
                    auxiliary("compact.type", symbol: "tag") { session.accessory = .type }
                    auxiliary("compact.more", symbol: "ellipsis") { session.overlay = .more }
                }
            }
            Group {
                switch session.accessory {
                case .digits: digits
                case .rpe: rpePanel
                case .type: typePanel
                case .weight: CompactWeightPanel(session: session)
                }
            }.frame(height: 188)
            HStack(spacing: 8) {
                Group {
                    if glass && !session.isEditingEquipmentDefault {
                        Button { session.navigation.jump(to: session.core.activeExerciseID, order: session.core.workoutIDs) } label: { inputContext }
                            .buttonStyle(.plain).accessibilityLabel(studioText("compact.locateEditor"))
                    } else { inputContext }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if session.isEditingEquipmentDefault { session.saveEquipmentDefault() }
                    else { session.save(complete: session.selectedSet?.completed != true) }
                } label: {
                    Label(session.isEditingEquipmentDefault ? studioText("weight.saveDefault") : (glass ? compactSetActionTitle(session: session, editing: true) : studioText(session.selectedSet?.completed == true ? "compact.saveEdits" : "compact.saveLog")), systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold)).frame(minWidth: 124, minHeight: 44)
                        .foregroundStyle(theme.primary.onPrimary).background(theme.primary.primary, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(session.isEditingEquipmentDefault ? !session.canSaveEquipmentDefault : !session.core.editorCanCommit)
            }.frame(height: 44)
        }.padding(.horizontal, 8).padding(.top, 6)
            .background(glass ? .clear : theme.neutrals.card)
            .modifier(CompactGlassSurface(radius: 20, snapshot: snapshot, enabled: glass))
    }
    private var inputContext: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if glass { Image(systemName: "scope").accessibilityHidden(true) }
                Text(session.isEditingEquipmentDefault ? studioText("exercise.short.\(session.core.activeExerciseID)") + " · " + studioText("weight.default") : (glass ? studioText("compact.editingShort") + " · " : "") + studioText("exercise.short.\(session.core.activeExerciseID)") + " · " + studioText("set.number") + " " + (session.selectedSetNumber.map(String.init) ?? "—"))
            }.font(.system(size: glass ? 13 : 11, weight: .semibold)).lineLimit(1)
            Text(session.isEditingEquipmentDefault ? studioText(session.canSaveEquipmentDefault ? "weight.defaultScopeShort" : "weight.defaultRange") : (session.core.editorError ?? session.core.notice ?? studioText("compact.commitHint")))
                .font(.system(size: 11)).foregroundStyle(session.isEditingEquipmentDefault ? (session.canSaveEquipmentDefault ? theme.neutrals.text2 : theme.danger) : (session.core.editorError == nil ? theme.neutrals.text2 : theme.danger)).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
    private func field(_ name: String, value: String) -> some View {
        let selected = session.core.editorField == name
        let label = studioText(name == "weightRight" ? "weight.rightUnit" : (name == "weight" && session.core.editorIsSplit ? "weight.leftUnit" : "set.\(name)"))
        return Button { session.core.switchEditor(to: name); session.core.editorSelectAll = true; session.accessory = .digits } label: {
            Group {
                if session.core.editorIsSplit {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(label).font(.system(size: 12))
                        HStack(spacing: 3) { Spacer(minLength: 0); fieldNumber(value, selected: selected) }
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(label).font(.system(size: 12))
                        Spacer(minLength: 0)
                        fieldNumber(value, selected: selected)
                        if name != "reps" { Text("kg").font(.caption) }
                    }
                }
            }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? theme.primary.primaryText : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityLabel(studioText(name == "weightRight" ? "weight.right" : "editor.\(name)"))
            .accessibilityValue(value).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func fieldNumber(_ value: String, selected: Bool) -> some View {
        HStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
                .background(selected && session.core.editorSelectAll ? theme.primary.primaryText.opacity(0.25) : .clear)
            if selected && !session.core.editorSelectAll {
                Capsule().fill(theme.primary.primaryText).frame(width: 1, height: 18).accessibilityHidden(true)
            }
        }
    }
    private func auxiliary(_ key: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 12)).accessibilityHidden(true)
                Text(studioText(key)).font(.caption2)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var digits: some View {
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { col in
                        let key = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "delete"][row * 3 + col]
                        Button {
                            if session.isEditingEquipmentDefault { session.pressEquipmentDefaultKey(key) }
                            else { session.core.pressEditorKey(key) }
                        } label: {
                            Group {
                                if key == "delete" { Image(systemName: "delete.left").font(.title3) }
                                else { Text(key).font(.system(size: 22, design: .rounded)).monospacedDigit() }
                            }.frame(maxWidth: .infinity, minHeight: 44)
                                .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).disabled(key == "." && !session.isEditingEquipmentDefault && session.core.editorField == "reps")
                            .accessibilityLabel(key == "delete" ? studioText("action.deleteDigit") : key)
                            .accessibilityAddTraits(.isKeyboardKey)
                    }
                }
            }
        }
    }
    private var rpePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(studioText("compact.rpeTitle")).font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                ForEach(6...10, id: \.self) { value in
                    Button { session.setRPE(value) } label: {
                        Text(String(value)).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                            .background(session.currentRPE == value ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6).strokeBorder(session.currentRPE == value ? theme.primary.primaryText : .clear, lineWidth: 1)
                            }
                            .overlay(alignment: .topTrailing) {
                                if session.currentRPE == value { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).padding(4).accessibilityHidden(true) }
                            }
                    }.buttonStyle(.plain).accessibilityAddTraits(session.currentRPE == value ? .isSelected : [])
                }
            }
            HStack {
                Button { session.setRPE(nil) } label: {
                    Text(studioText("compact.unset")).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
                }
                Spacer()
                Button { session.accessory = .digits } label: {
                    Text(studioText("compact.backDigits")).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
                }
            }.buttonStyle(.plain).font(.subheadline)
            Text(studioText("compact.accessoryHint")).font(.caption).foregroundStyle(theme.neutrals.text2)
        }.padding(8).frame(maxHeight: .infinity, alignment: .top)
    }
    private var typePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(studioText("compact.type")).font(.subheadline.weight(.semibold))
            HStack {
                ForEach(["warmup", "working"], id: \.self) { kind in
                    Button { session.setKind(kind) } label: {
                        Text(studioText("set.\(kind)")).font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(session.currentKind == kind ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
            }
            Button { session.overlay = .advanced } label: {
                Text(studioText("compact.advanced")).font(.caption).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { session.accessory = .digits } label: {
                Text(studioText("compact.backDigits")).font(.caption).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(8).frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct CompactPickerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: CompactSession
    @Bindable var model: CompactPickerModel
    let snapshot: Bool
    @State private var anchor = "barbell"
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(studioText(session.core.replacementID == nil ? "picker.title" : "picker.replace")).font(.headline)
                Spacer()
                Text("\(model.resultCount) " + studioText("picker.results")).font(.caption).foregroundStyle(theme.neutrals.text2)
            }.padding(.horizontal, 12).frame(height: 44).overlay(alignment: .bottom) { Divider() }
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    CompactViewport(snapshot: snapshot) {
                        VStack(spacing: 0) {
                            ForEach(model.sections) { section in
                                Button { anchor = section.id; searchFocused = false; proxy.scrollTo(section.id, anchor: .top) } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: section.id == "bodyweight" ? "figure.strengthtraining.traditional" : "dumbbell").font(.system(size: 15)).accessibilityHidden(true)
                                        Text(studioText("equipment.\(section.id)")).font(.caption2).multilineTextAlignment(.center)
                                        Text(String(section.items.count)).font(.caption2).foregroundStyle(theme.neutrals.text2)
                                    }.frame(width: 64, height: 72).background(anchor == section.id ? theme.primary.primarySubtle : .clear)
                                }.buttonStyle(.plain).accessibilityAddTraits(anchor == section.id ? .isSelected : [])
                            }
                        }
                    }.frame(width: 64).scrollIndicators(.hidden)
                    Divider()
                    CompactViewport(snapshot: snapshot) { results }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                }
                .onChange(of: model.generation) { _, _ in
                    if let first = model.sections.first { anchor = first.id; proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").accessibilityHidden(true)
                        if snapshot {
                            Text(model.query.isEmpty ? studioText("picker.search") : model.query).foregroundStyle(theme.neutrals.text2).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField(studioText("picker.search"), text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                        }
                        if !model.query.isEmpty {
                            StudioIconButton(symbol: "xmark.circle.fill", label: studioText("picker.clearQuery")) { model.query = "" }
                        }
                    }.font(.subheadline).padding(.horizontal, 10).frame(minHeight: 44).background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 8))
                    CompactTool(title: studioText("compact.filter"), symbol: model.muscle == "all" && model.equipment == "all" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                        searchFocused = false; session.overlay = .filters
                    }
                }
                HStack(spacing: 8) {
                    Button { searchFocused = false; session.core.replacementID = nil; session.core.screen = .workout } label: {
                        Text(studioText("action.cancel")).frame(minWidth: 52, minHeight: 44).contentShape(Rectangle())
                    }
                    Button { searchFocused = false; session.overlay = .selection } label: {
                        Text(studioText("compact.selectedCount") + " \(session.core.selectedIDs.count)").font(.caption)
                            .frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                    Button { searchFocused = false; session.core.confirmSelection() } label: {
                        Text(studioText("compact.addSelected") + " (\(session.core.selectedIDs.count))").font(.subheadline.weight(.semibold))
                            .frame(minWidth: 118, minHeight: 44).foregroundStyle(theme.primary.onPrimary)
                            .background(theme.primary.primary, in: RoundedRectangle(cornerRadius: 8))
                    }.disabled(session.core.selectedIDs.isEmpty)
                }.buttonStyle(.plain)
            }.padding(8).background(theme.neutrals.card).overlay(alignment: .top) { Divider() }
        }
        .task(id: model.requestKey) {
            if !snapshot { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }; model.refresh()
        }
    }
    @ViewBuilder private var results: some View {
        if model.sections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(studioText("compact.noResults")).font(.headline)
                Text(studioText("compact.keepSearching")).font(.caption).foregroundStyle(theme.neutrals.text2)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(studioText("equipment.\(section.id)")).font(.caption.weight(.semibold)).foregroundStyle(theme.neutrals.text2).frame(minHeight: 28).id(section.id)
                    // Eager section rows + one parent LazyVStack, no nested lazy grids.
                    let columns = typeSize.isAccessibilitySize ? 1 : 2
                    ForEach(0..<((section.items.count + columns - 1) / columns), id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(Array(section.items.dropFirst(row * columns).prefix(columns))) { exercise in card(exercise) }
                            if columns == 2 && row * columns + 1 >= section.items.count { Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }
    private func card(_ exercise: StudioExercise) -> some View {
        let selected = session.core.selectedIDs.contains(exercise.id)
        return Button { searchFocused = false; session.core.toggleSelection(exercise.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(studioText("muscle.\(exercise.muscle)")).font(.caption2).foregroundStyle(theme.neutrals.text2)
                    Spacer(minLength: 0)
                    if let index = session.core.selectedIDs.firstIndex(of: exercise.id) {
                        Text(String(index + 1)).font(.caption2.bold()).foregroundStyle(theme.primary.primaryText)
                    } else { Image(systemName: "plus").font(.caption2).accessibilityHidden(true) }
                }
                Text(exercise.name).font(.subheadline.weight(.medium)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }.padding(8).frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? theme.primary.primaryBorder : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CompactDrawer: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    @Bindable var picker: CompactPickerModel
    let kind: CompactOverlay
    let snapshot: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25).onTapGesture { session.overlay = nil }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(studioText("compact.drawer.\(kind.rawValue)")).font(.headline)
                    Spacer()
                    StudioIconButton(symbol: "xmark", label: studioText("action.dismiss")) { session.overlay = nil }
                }.padding(.horizontal, 16).frame(height: 52)
                Divider()
                CompactViewport(snapshot: snapshot) {
                    VStack(alignment: .leading, spacing: 4) {
                        switch kind {
                        case .more: more
                        case .filters: filters
                        case .selection: selection
                        case .finish: finish
                        case .advanced: advanced
                        }
                    }.padding(16)
                }.scrollIndicators(.hidden)
            }.frame(maxHeight: kind == .more ? 580 : (kind == .filters ? 430 : 350))
                .modifier(CompactGlassSurface(radius: 22, snapshot: snapshot))
                .padding(.horizontal, 8).padding(.bottom, 16)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityAddTraits(.isModal)
    }
    private func heading(_ key: String) -> some View {
        Text(studioText(key)).font(.caption.weight(.semibold)).foregroundStyle(theme.neutrals.text2).padding(.top, 8)
    }
    private func row(_ key: String, symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(destructive ? destructiveColor : theme.neutrals.text1).accessibilityHidden(true)
                Text(studioText(key)).font(.subheadline).foregroundStyle(destructive ? destructiveColor : theme.neutrals.text1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(theme.neutrals.text2).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var destructiveColor: Color { theme.isDark ? theme.danger : theme.danger.mix(with: .black, by: 0.2) }
    @ViewBuilder private var more: some View {
        Text(session.core.activeExercise.name + " · " + studioText("set.number") + " " + (session.selectedSetNumber.map(String.init) ?? "—"))
            .font(.caption).foregroundStyle(theme.neutrals.text2)
        if session.core.editorField != nil {
            row("keyboard.cancel", symbol: "arrow.uturn.backward") { session.discardDraft(); session.overlay = nil }
        }
        heading("compact.scope.set")
        row("weight.entry", symbol: "arrow.left.arrow.right") { session.edit("weight"); session.accessory = .weight; session.overlay = nil }
        HStack {
            row("compact.type", symbol: "tag") { session.edit("weight"); session.accessory = .type; session.overlay = nil }
            row("compact.rpe", symbol: "gauge.with.dots.needle.50percent") { session.edit("weight"); session.accessory = .rpe; session.overlay = nil }
        }
        row("keyboard.copy", symbol: "doc.on.doc") { session.edit("weight"); session.core.copyEditorToNext(); session.overlay = nil }
        row("set.delete", symbol: "trash", destructive: true) { session.deleteSelected() }.disabled(session.core.activeSets.count <= 1)
        heading("compact.scope.exercise")
        if session.supportsEquipmentDefault {
            row("weight.default", symbol: "slider.horizontal.3") { session.beginEquipmentDefault() }
            if session.equipmentDefault != nil {
                row("weight.clearDefault", symbol: "minus.circle") { session.clearEquipmentDefault(); session.overlay = nil }
            }
        }
        row("compact.addSet", symbol: "plus") { session.addSet(); session.overlay = nil }
        row("compact.replaceExercise", symbol: "arrow.triangle.2.circlepath") { session.showPicker(replacing: true) }
        row("compact.advanced", symbol: "slider.horizontal.3") { session.overlay = .advanced }
        heading("compact.scope.workout")
        row("compact.addExercise", symbol: "plus.square.on.square") { session.showPicker() }
        row("compact.finishPrompt", symbol: "stop.circle") { session.overlay = .finish }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("compact.muscle")
            ForEach([["all", "chest", "back", "shoulders"], ["legs", "arms", "core"]], id: \.self) { group in
                HStack(spacing: 4) {
                    ForEach(group, id: \.self) { value in
                        filterChip(studioText("muscle.\(value)"), selected: picker.muscle == value) { picker.muscle = value }
                    }
                }
            }
            heading("compact.equipment")
            VStack(spacing: 8) {
                ForEach([["all", "barbell", "dumbbell"], ["cable", "machine", "bodyweight"]], id: \.self) { group in
                    HStack(spacing: 8) {
                        ForEach(group, id: \.self) { value in
                            filterChip(studioText("equipment.\(value)"), selected: picker.equipment == value) { picker.equipment = value }
                        }
                    }
                }
            }
            HStack {
                Button { picker.reset() } label: {
                    Text(studioText("picker.reset")).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
                }
                Spacer()
                Button { picker.refresh(); session.overlay = nil } label: {
                    Text(studioText("compact.applyFilter")).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
                }
            }.buttonStyle(.plain).font(.subheadline.weight(.semibold))
        }
    }
    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).accessibilityHidden(true) }
                Text(title).font(.caption.weight(selected ? .semibold : .regular)).multilineTextAlignment(.center)
            }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? theme.primary.primaryText : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var selection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(session.core.selectedIDs.enumerated()), id: \.element) { index, id in
                Button { session.core.toggleSelection(id) } label: {
                    HStack {
                        Text("\(index + 1)").monospacedDigit()
                        Text(studioText("exercise.\(id)"))
                        Spacer()
                        Image(systemName: "xmark.circle").accessibilityHidden(true)
                    }.font(.subheadline).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            if session.core.selectedIDs.isEmpty { Text(studioText("compact.noneSelected")).font(.subheadline) }
        }
    }
    private var finish: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(studioText("finish.message")).font(.subheadline)
            Text(studioText("compact.finishHint")).font(.caption).foregroundStyle(theme.neutrals.text2)
            Button { session.finish() } label: {
                Text(studioText("finish.confirm")).frame(minWidth: 88, minHeight: 44).contentShape(Rectangle())
            }.disabled(session.core.editorField != nil && !session.core.editorCanCommit)
            Button { session.overlay = nil } label: {
                Text(studioText("action.cancel")).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }
    private var advanced: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(studioText("compact.advancedIntro")).font(.subheadline)
            Text(studioText("compact.advancedBody")).font(.subheadline).foregroundStyle(theme.neutrals.text2)
            Text(studioText("compact.advancedBoundary")).font(.caption).foregroundStyle(theme.neutrals.text2)
        }
    }
}

#Preview("Compact rail light") {
    CompactStudioView(session: CompactSession(), layout: .rail)
        .environment(\.theme, Theme(seed: .blue, neutral: .slate, isDark: false)).frame(width: 393, height: 852)
}
#Preview("Compact rail dark") {
    CompactStudioView(session: CompactSession(), layout: .rail)
        .environment(\.theme, Theme(seed: .blue, neutral: .slate, isDark: true)).environment(\.colorScheme, .dark).frame(width: 393, height: 852)
}

// ImageRenderer on macOS does not paint offscreen NSScrollView content. Export the
// identical eager content inside a clipped viewport; runtime keeps one lazy scroll.
private struct CompactViewport<Content: View>: View {
    let snapshot: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            if snapshot {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .frame(width: geometry.size.width, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading).clipped()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) { content() }
                }.scrollIndicators(.hidden)
            }

        }
    }
}

private struct CompactStateView: View {
    @Environment(\.theme) private var theme
    let state: CompactContentState
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(theme.primary.primary)
            Text(studioText(titleKey)).font(.headline)
            Text(studioText(detailKey)).font(.caption).foregroundStyle(theme.neutrals.text2)
            if state == .error {
                Button(studioText("compact.retry"), action: retry)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(CompactPressStyle())
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .background(theme.neutrals.card)
    }
    private var icon: String {
        switch state { case .populated: "checkmark"; case .empty: "tray"; case .loading: "hourglass"; case .error: "exclamationmark.triangle" }
    }
    private var titleKey: String {
        switch state { case .populated: "compact.state"; case .empty: "compact.emptyState"; case .loading: "compact.loadingState"; case .error: "compact.errorState" }
    }
    private var detailKey: String {
        switch state { case .populated: "compact.state"; case .empty: "compact.emptyDetail"; case .loading: "compact.loadingDetail"; case .error: "compact.errorDetail" }
    }
}
