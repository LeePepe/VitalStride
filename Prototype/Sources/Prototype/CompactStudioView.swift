import DesignKit
import SwiftUI

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
            if session.core.screen == .picker {
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
                CompactWorkoutBody(session: session, layout: layout, snapshot: snapshot)
                CompactStatusLine(session: session)
                if session.core.editorField != nil { CompactKeyboard(session: session) }
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
    private var workoutActions: some View {
        HStack(spacing: 8) {
            CompactTool(title: studioText("compact.more"), symbol: "ellipsis") { session.overlay = .more }
            CompactTool(title: studioText("compact.addSet"), symbol: "plus") { session.addSet() }
            Button { session.completeSelected() } label: {
                Label(studioText(session.selectedSet?.completed == true ? "set.uncomplete" : "compact.logSet"), systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(theme.primary.onPrimary).background(theme.primary.primary, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(session.selectedSet == nil)
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
        if layout == .rail {
            HStack(spacing: 0) {
                exerciseRail
                Divider()
                activeDetail
            }
        } else {
            ScrollViewReader { proxy in
                CompactViewport(snapshot: snapshot) { sectionContent }
                .scrollIndicators(.hidden)
                .onChange(of: session.core.editorField != nil) { _, editing in
                    if editing { proxy.scrollTo(session.core.activeExerciseID, anchor: .top) }
                }
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
    private var exerciseRail: some View {
        CompactViewport(snapshot: snapshot) {
            VStack(spacing: 0) {
                ForEach(Array(session.core.workoutIDs.enumerated()), id: \.element) { index, id in
                    Button { session.select(exercise: id) } label: {
                        VStack(spacing: 4) {
                            Text(String(index + 1)).font(.caption).foregroundStyle(theme.neutrals.text2)
                            Text(studioText("exercise.short.\(id)")).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                            let sets = session.core.setsByExercise[id] ?? []
                            Text("\(sets.filter(\.completed).count)/\(sets.count)").font(.caption2).monospacedDigit()
                        }.frame(width: 64, height: 76)
                            .background(session.core.activeExerciseID == id ? theme.primary.primarySubtle : .clear)
                    }.buttonStyle(.plain).accessibilityAddTraits(session.core.activeExerciseID == id ? .isSelected : [])
                }
            }
        }.frame(width: 64).scrollIndicators(.hidden)
    }
    private var activeDetail: some View {
        CompactViewport(snapshot: snapshot) {
            activeTable
        }.scrollIndicators(.hidden)
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

private struct CompactSetRow: View {
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
            Button { if session.select(exercise: exerciseID, setID: set.id) { session.edit("weight") } } label: {
                Text(editing ? session.core.editorWeightText : set.weight.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 48).background(theme.neutrals.card.opacity(selected ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).accessibilityLabel(studioText("editor.weight"))
            Button { if session.select(exercise: exerciseID, setID: set.id) { session.edit("reps") } } label: {
                Text(editing ? session.core.editorRepsText : String(set.reps)).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                    .frame(width: 48, height: 48).background(theme.neutrals.card.opacity(selected ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).accessibilityLabel(studioText("editor.reps"))
            Button { if session.select(exercise: exerciseID, setID: set.id) { session.completeSelected() } } label: {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(set.completed ? theme.success : theme.neutrals.text2).frame(width: 44, height: 48)
            }.buttonStyle(.plain).accessibilityLabel(studioText(set.completed ? "set.uncomplete" : "set.complete"))
        }.padding(.horizontal, 12).padding(.vertical, 2)
            .background(selected ? theme.primary.primarySubtle : .clear)
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(theme.primary.primary).frame(width: 2).padding(.vertical, 8).accessibilityHidden(true) }
            }
            .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? .isSelected : [])
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
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                field("weight", value: session.core.editorWeightText)
                field("reps", value: session.core.editorRepsText)
                StudioIconButton(symbol: "keyboard.chevron.compact.down", label: studioText("keyboard.saveClose")) { session.save() }
                    .disabled(!session.core.editorCanCommit)
            }
            HStack(spacing: 4) {
                auxiliary("compact.previous", symbol: "clock.arrow.circlepath") { session.core.usePreviousEditorValues() }
                auxiliary("compact.copy", symbol: "doc.on.doc") { session.core.copyEditorToNext() }
                    .disabled(!session.core.editorCanCommit)
                auxiliary("compact.rpe", symbol: "gauge.with.dots.needle.50percent") { session.accessory = .rpe }
                auxiliary("compact.type", symbol: "tag") { session.accessory = .type }
                auxiliary("compact.more", symbol: "ellipsis") { session.overlay = .more }
            }
            Group {
                switch session.accessory {
                case .digits: digits
                case .rpe: rpePanel
                case .type: typePanel
                }
            }.frame(height: 188)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(studioText("exercise.short.\(session.core.activeExerciseID)") + " · " + studioText("set.number") + " " + (session.selectedSetNumber.map(String.init) ?? "—"))
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(session.core.editorError ?? session.core.notice ?? studioText("compact.commitHint"))
                        .font(.system(size: 11)).foregroundStyle(session.core.editorError == nil ? theme.neutrals.text2 : theme.danger).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { session.save(complete: session.selectedSet?.completed != true) } label: {
                    Label(studioText(session.selectedSet?.completed == true ? "compact.saveEdits" : "compact.saveLog"), systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold)).frame(minWidth: 124, minHeight: 44)
                        .foregroundStyle(theme.primary.onPrimary).background(theme.primary.primary, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(!session.core.editorCanCommit)
            }.frame(height: 44)
        }.padding(.horizontal, 8).padding(.top, 6).background(theme.neutrals.card)
    }
    private func field(_ name: String, value: String) -> some View {
        let selected = session.core.editorField == name
        return Button { session.core.switchEditor(to: name); session.core.editorSelectAll = true; session.accessory = .digits } label: {
            HStack(spacing: 8) {
                Text(studioText("set.\(name)")).font(.caption)
                Spacer(minLength: 0)
                Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                    .background(selected && session.core.editorSelectAll ? theme.primary.primaryBorder.opacity(0.4) : .clear)
                if name == "weight" { Text("kg").font(.caption) }
            }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel(studioText("editor.\(name)"))
            .accessibilityValue(value).accessibilityAddTraits(selected ? .isSelected : [])
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
                        Button { session.core.pressEditorKey(key) } label: {
                            Group {
                                if key == "delete" { Image(systemName: "delete.left").font(.title3) }
                                else { Text(key).font(.system(size: 22, design: .rounded)).monospacedDigit() }
                            }.frame(maxWidth: .infinity, minHeight: 44)
                                .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).disabled(key == "." && session.core.editorField == "reps")
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
                .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8).padding(.bottom, 16)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityAddTraits(.isModal)
    }
    private func heading(_ key: String) -> some View {
        Text(studioText(key)).font(.caption.weight(.semibold)).foregroundStyle(theme.neutrals.text2).padding(.top, 8)
    }
    private func row(_ key: String, symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(destructive ? theme.danger : theme.neutrals.text1).accessibilityHidden(true)
                Text(studioText(key)).font(.subheadline).foregroundStyle(destructive ? theme.danger : theme.neutrals.text1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(theme.neutrals.text2).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var more: some View {
        Text(session.core.activeExercise.name + " · " + studioText("set.number") + " " + (session.selectedSetNumber.map(String.init) ?? "—"))
            .font(.caption).foregroundStyle(theme.neutrals.text2)
        if session.core.editorField != nil {
            row("keyboard.cancel", symbol: "arrow.uturn.backward") { session.discardDraft(); session.overlay = nil }
        }
        heading("compact.scope.set")
        HStack {
            row("compact.type", symbol: "tag") { session.edit("weight"); session.accessory = .type; session.overlay = nil }
            row("compact.rpe", symbol: "gauge.with.dots.needle.50percent") { session.edit("weight"); session.accessory = .rpe; session.overlay = nil }
        }
        row("keyboard.copy", symbol: "doc.on.doc") { session.edit("weight"); session.core.copyEditorToNext(); session.overlay = nil }
        row("set.delete", symbol: "trash", destructive: true) { session.deleteSelected() }.disabled(session.core.activeSets.count <= 1)
        heading("compact.scope.exercise")
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
            HStack(spacing: 4) {
                ForEach(["all", "barbell", "dumbbell", "cable", "bodyweight"], id: \.self) { value in
                    filterChip(studioText("equipment.\(value)"), selected: picker.equipment == value) { picker.equipment = value }
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
            Text(title).font(.caption).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? theme.primary.primarySubtle : theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 6))
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

#Preview("Compact table") {
    CompactStudioView(session: CompactSession(), layout: .table)
        .environment(\.theme, Theme(seed: .blue, neutral: .slate, isDark: false)).frame(width: 393, height: 852)
}
#Preview("Compact matrix dark") {
    CompactStudioView(session: CompactSession(), layout: .matrix)
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
