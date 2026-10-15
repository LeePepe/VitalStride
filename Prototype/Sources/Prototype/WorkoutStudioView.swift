import DesignKit
import SwiftUI

/// Same native view powers the interactive studio and the rendered comparison.
/// `snapshot` uses eager rows only; runtime uses a single ScrollView/LazyVStack.
public struct WorkoutStudioView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable private var session: StudioSession
    private let style: StudioStyle
    private let layout: StudioLayout
    private let snapshot: Bool
    @State private var confirmingFinish = false
    @State private var showSelection = false
    @State private var showBoardWarmupRows = false
    @ScaledMetric(relativeTo: .largeTitle) private var focusNumberSize = 58
    @ScaledMetric(relativeTo: .caption) private var statusLabelSize = 12

    public init(session: StudioSession, style: StudioStyle, layout: StudioLayout, snapshot: Bool = false) {
        self.session = session
        self.style = style
        self.layout = layout
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(spacing: 0) {
            statusBar
            navigation
            if session.isFinished {
                finishedContent
            } else {
                if session.screen == .picker { pickerHeader } else { workoutHeader }
                contentViewport
                bottomDock
            }
            Capsule().fill(theme.neutrals.text1).frame(width: 120, height: 4)
                .padding(.top, 8).padding(.bottom, 8).accessibilityHidden(true)
        }
        .background(theme.neutrals.bg)
        .foregroundStyle(theme.neutrals.text1)
        .clipped()
        .alert(studioText("finish.title"), isPresented: $confirmingFinish) {
            Button(studioText("finish.confirm")) { session.isFinished = true; session.restEnd = nil; session.deletedSet = nil }
            Button(studioText("action.cancel"), role: .cancel) {}
        } message: { Text(studioText("finish.message")) }
        .sheet(isPresented: $showSelection) { selectionSheet }
    }

    private var statusBar: some View {
        HStack {
            Text("9:41").font(.system(size: 14, weight: .semibold)).monospacedDigit()
            Spacer()
            Text(studioText("demo.badge")).font(.system(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(theme.neutrals.text2)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }.font(.system(size: 11)).accessibilityHidden(true)
        }.padding(.horizontal, 24).frame(height: 32)
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            if session.screen == .picker {
                StudioIconButton(symbol: "xmark", label: studioText("action.cancel"), filled: true) {
                    session.replacementID = nil; session.screen = .workout
                }
            } else {
                StudioIconButton(symbol: session.isFinished ? "xmark" : "chevron.down",
                                 label: studioText(session.isFinished ? "action.done" : "workout.minimize"), filled: true) {
                    if session.isFinished { session.isFinished = false; session.screen = .picker }
                    else { session.notice = studioText("workout.minimizeNote") }
                }
            }
            Spacer()
            Text(studioText(session.isFinished ? "finish.context" : (session.screen == .picker ? "picker.context" : "workout.context")))
                .font(.system(.caption, weight: .semibold)).tracking(style == .graphite ? 2 : 1)
                .foregroundStyle(theme.neutrals.text2)
            Spacer()
            if session.screen == .picker {
                StudioIconButton(symbol: "list.bullet", label: studioText("picker.reviewSelection")) { showSelection = true }
            } else {
                Button(studioText(session.isFinished ? "action.done" : "workout.finish")) {
                    if session.isFinished { session.isFinished = false; session.screen = .picker }
                    else { confirmingFinish = true }
                }
                    .font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.plain).foregroundStyle(theme.primary.primaryText)
            }
        }.padding(.horizontal, 16).frame(minHeight: 52)
    }

    private func title(_ text: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(style == .graphite ? .title : .largeTitle, design: style == .ember ? .serif : .default, weight: .bold))
            Text(subtitle).font(.subheadline).foregroundStyle(theme.neutrals.text2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pickerHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if layout == .focus {
                Text(studioText(session.replacementID == nil ? "picker.title" : "picker.replace"))
                    .font(.system(.title, design: style == .ember ? .serif : .default, weight: .bold))
            } else {
                title(studioText(session.replacementID == nil ? "picker.title" : "picker.replace"), subtitle: studioText("picker.subtitle"))
            }
            searchField
            if layout != .board || typeSize.isAccessibilitySize { muscleFilters }
            equipmentFilter
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
        .background(style == .ember ? theme.primary.primarySubtle.opacity(0.45) : .clear)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.body).foregroundStyle(theme.neutrals.text2).accessibilityHidden(true)
            if snapshot {
                Text(session.query.isEmpty ? studioText("picker.search") : session.query)
                    .font(.body).foregroundStyle(theme.neutrals.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(studioText("picker.search"), text: $session.query)
                    .textFieldStyle(.plain).font(.body)
                    .accessibilityLabel(studioText("picker.search"))
            }
            if !session.query.isEmpty {
                StudioIconButton(symbol: "xmark.circle.fill", label: studioText("picker.clearQuery")) { session.query = "" }
            }
        }
        .padding(.leading, 16).padding(.trailing, 4).frame(minHeight: 48)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: style == .graphite ? 10 : 14))
    }

    private var muscleFilters: some View {
        horizontalStrip {
            HStack(spacing: 8) {
                ForEach(["all", "chest", "back", "shoulders", "legs", "arms", "core"], id: \.self) { muscle in
                    StudioChip(title: studioText("muscle.\(muscle)"), selected: session.muscle == muscle) { session.muscle = muscle }
                }
            }
        }.frame(height: 44)
    }

    @ViewBuilder private func horizontalStrip<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        if snapshot {
            GeometryReader { geometry in
                content().fixedSize(horizontal: true, vertical: false)
                    .frame(width: geometry.size.width, alignment: .leading).clipped()
            }.frame(height: 44)
        } else {
            ScrollView(.horizontal) { content() }.scrollIndicators(.hidden)
        }
    }

    private var equipmentLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease").accessibilityHidden(true)
            Text(studioText("equipment.\(session.equipment)"))
            Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
        }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
    }

    private var equipmentFilter: some View {
        HStack {
            if snapshot { equipmentLabel }
            else {
                Menu {
                    ForEach(["all", "barbell", "dumbbell", "cable", "bodyweight"], id: \.self) { item in
                        Button(studioText("equipment.\(item)")) { session.equipment = item }
                    }
                } label: { equipmentLabel }.menuStyle(.borderlessButton).fixedSize()
            }
            Spacer()
            if session.muscle != "all" || session.equipment != "all" {
                Button(studioText("picker.reset")) { session.clearFilters() }
                    .buttonStyle(.plain).font(.caption).frame(minHeight: 44)
            } else {
                Text("\(session.results.count) " + studioText("picker.results"))
                    .font(.caption).foregroundStyle(theme.neutrals.text2).monospacedDigit()
            }
        }.foregroundStyle(theme.neutrals.text2).frame(height: 44)
    }

    private var workoutHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(studioText("workout.title"))
                    .font(.system(.title, design: style == .ember ? .serif : .default, weight: .bold))
                Spacer()
                Text(studioText("workout.watchOffline"))
                    .font(.caption).foregroundStyle(theme.neutrals.text2)
            }
            if (layout == .focus || session.editorField != nil) && !typeSize.isAccessibilitySize {
                HStack {
                    Text("24:18").monospacedDigit()
                    Text("·").accessibilityHidden(true)
                    Text("\(session.completedCount)/\(session.totalCount) " + studioText("workout.setUnit"))
                    Spacer()
                    Text("\((session.workoutIDs.firstIndex(of: session.activeExerciseID) ?? 0) + 1)/\(session.workoutIDs.count)")
                }.font(.subheadline.weight(.medium)).foregroundStyle(theme.neutrals.text2)
            } else {
                StudioSessionBand(session: session, style: style)
            }
            if layout != .board && session.editorField == nil { exerciseTabs }
            progressTrack
        }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
    }

    private var exerciseTabs: some View {
        horizontalStrip {
            HStack(spacing: 8) {
                ForEach(Array(session.workoutIDs.enumerated()), id: \.element) { index, id in
                    StudioChip(title: "\(index + 1) " + studioText("exercise.short.\(id)"), selected: session.activeExerciseID == id) {
                        session.activeExerciseID = id
                    }
                }
                StudioIconButton(symbol: "plus", label: studioText("workout.addExercise")) { session.screen = .picker }
            }
        }.frame(height: 44)
    }

    private var progressTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.neutrals.border)
                Capsule().fill(theme.primary.primary)
                    .frame(width: proxy.size.width * Double(session.completedCount) / Double(max(1, session.totalCount)))
            }
        }.frame(height: 3)
            .accessibilityLabel(studioText("workout.progress"))
            .accessibilityValue("\(session.completedCount) / \(session.totalCount)")
    }

    private var contentViewport: some View {
        GeometryReader { geometry in
            Group {
                if snapshot {
                    pageContent.frame(width: geometry.size.width, alignment: .top)
                } else {
                    ScrollViewReader { reader in
                        ScrollView { pageContent }.scrollIndicators(.hidden)
                            .onChange(of: session.editorField) { _, field in
                                if field != nil, let id = session.currentSet?.id { reader.scrollTo(id, anchor: .center) }
                            }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
        }
    }

    @ViewBuilder private var pageContent: some View {
        if session.screen == .picker {
            if session.results.isEmpty { pickerEmpty }
            else if layout == .focus && !typeSize.isAccessibilitySize { pickerGrid }
            else if layout == .board && !typeSize.isAccessibilitySize { pickerBoard }
            else { pickerList }
        } else if layout == .focus && !typeSize.isAccessibilitySize {
            focusWorkout
        } else if layout == .board && !typeSize.isAccessibilitySize {
            boardWorkout
        } else { flowWorkout }
    }

    private var pickerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(studioText("picker.library"), trailing: studioText("picker.nameOrder"))
            if snapshot {
                ForEach(session.results) { exercise in exerciseRow(exercise) }
            } else {
                LazyVStack(spacing: 0) { ForEach(session.results) { exercise in exerciseRow(exercise) } }
            }
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }

    private var pickerGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(studioText("picker.library"), trailing: studioText("picker.tapToChoose"))
            if snapshot {
                let items = session.results
                ForEach(0..<((items.count + 1) / 2), id: \.self) { row in
                    HStack(alignment: .top, spacing: 12) {
                        exerciseTile(items[row * 2])
                        if row * 2 + 1 < items.count { exerciseTile(items[row * 2 + 1]) }
                        else { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(session.results) { exercise in exerciseTile(exercise) }
                }
            }
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }

    private var pickerBoard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ForEach(["all", "chest", "back", "shoulders", "legs", "arms", "core"], id: \.self) { muscle in
                    Button { session.muscle = muscle } label: {
                        Text(studioText("muscle.\(muscle)"))
                            .font(.system(.caption, weight: session.muscle == muscle ? .bold : .medium))
                            .frame(width: 60).frame(minHeight: 48)
                            .foregroundStyle(session.muscle == muscle ? theme.primary.primaryText : theme.neutrals.text2)
                            .background(session.muscle == muscle ? theme.primary.primarySubtle : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(session.muscle == muscle ? .isSelected : [])
                }
            }.padding(4).background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: style.radius))
            VStack(spacing: 0) {
                sectionLabel(studioText("picker.library"), trailing: "\(session.results.count)")
                ForEach(session.results) { exercise in exerciseRow(exercise, compact: true) }
            }
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }

    private func sectionLabel(_ title: String, trailing: String = "") -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).tracking(style == .graphite ? 1 : 0)
            Spacer()
            Text(trailing).font(.caption)
        }.foregroundStyle(theme.neutrals.text2).padding(.vertical, 8)
    }

    private func exerciseRow(_ exercise: StudioExercise, compact: Bool = false) -> some View {
        let index = session.selectedIDs.firstIndex(of: exercise.id)
        return Button { session.toggleSelection(exercise.id) } label: {
            HStack(spacing: 12) {
                if !compact {
                    Image(systemName: exercise.symbol).font(.system(size: 20, weight: .medium))
                        .foregroundStyle(index == nil ? theme.neutrals.text2 : theme.primary.primaryText)
                        .frame(width: 44, height: 44)
                        .background(index == nil ? theme.neutrals.inner : theme.primary.primarySubtle,
                                    in: RoundedRectangle(cornerRadius: style == .graphite ? 8 : 12))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(exercise.name).font(.system(.body, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(exercise.detail).font(.caption).foregroundStyle(theme.neutrals.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StudioSelectionMark(index: index)
            }
            .padding(.vertical, compact ? 16 : (style == .graphite ? 8 : 12))
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { theme.neutrals.border.frame(height: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(exercise.name + ", " + exercise.detail)
        .accessibilityValue(index.map { studioText("picker.selected") + " \($0 + 1)" } ?? studioText("picker.notSelected"))
        .accessibilityAddTraits(index == nil ? [] : .isSelected)
    }

    private func exerciseTile(_ exercise: StudioExercise) -> some View {
        let index = session.selectedIDs.firstIndex(of: exercise.id)
        return Button { session.toggleSelection(exercise.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: exercise.symbol).font(.system(size: 22, weight: .medium))
                        .foregroundStyle(index == nil ? theme.neutrals.text2 : theme.primary.primaryText).accessibilityHidden(true)
                    Spacer()
                    StudioSelectionMark(index: index)
                }
                Text(exercise.name).font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(studioText("equipment.\(exercise.equipment)"))
                    .font(.caption).foregroundStyle(theme.neutrals.text2)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(StudioSurface(style: style, emphasized: index != nil))
        }.buttonStyle(.plain).accessibilityLabel(exercise.name + ", " + exercise.detail)
            .accessibilityValue(index.map { studioText("picker.selected") + " \($0 + 1)" } ?? studioText("picker.notSelected"))
            .accessibilityAddTraits(index == nil ? [] : .isSelected)
    }

    private var pickerEmpty: some View {
        VStack(spacing: 16) {
            Image(systemName: session.emptyLibrary ? "tray" : "magnifyingglass").font(.largeTitle)
                .foregroundStyle(theme.neutrals.text2).accessibilityHidden(true)
            Text(studioText(session.emptyLibrary ? "picker.emptyTitle" : "picker.noResults"))
                .font(.title3.weight(.semibold))
            Text(studioText(session.emptyLibrary ? "picker.emptyDescription" : "picker.noResultsDescription"))
                .font(.body).foregroundStyle(theme.neutrals.text2).multilineTextAlignment(.center)
            if !session.emptyLibrary {
                StudioAction(title: studioText("picker.reset"), symbol: "arrow.counterclockwise", style: style) { session.clearFilters() }
            } else {
                StudioAction(title: studioText("picker.importDemo"), symbol: "square.and.arrow.down", style: style) {
                    session.emptyLibrary = false
                }
            }
        }.padding(32).padding(.top, 32)
    }

    private var flowWorkout: some View {
        VStack(alignment: .leading, spacing: 16) {
            exerciseHeading
            setTable
            addSetButton
            nextExerciseCard
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }

    private var exerciseHeading: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.activeExercise.name).font(.system(.title2, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(studioText("workout.last") + " 60 kg × 10").font(.subheadline).foregroundStyle(theme.neutrals.text2)
            }
            Spacer(minLength: 0)
            if snapshot {
                Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            } else { Menu {
                Button(studioText("workout.addSet")) { session.addSet() }
                Button(studioText("workout.replace")) {
                    session.replacementID = session.activeExerciseID; session.screen = .picker
                }
                Button(studioText("workout.moveFirst")) {
                    session.workoutIDs.removeAll { $0 == session.activeExerciseID }
                    session.workoutIDs.insert(session.activeExerciseID, at: 0)
                }
                Button(studioText("workout.advanced")) { session.notice = studioText("workout.advancedNote") }
            } label: {
                Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(studioText("workout.exerciseActions")) }
        }
    }

    private var setTable: some View {
        VStack(spacing: 0) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text(studioText("set.number")).frame(width: 40, alignment: .leading)
                    Text(studioText("set.previous")).frame(maxWidth: .infinity, alignment: .leading)
                    Text("kg").frame(width: 60)
                    Text(studioText("set.reps")).frame(width: 48)
                    Image(systemName: "checkmark").frame(width: 32).accessibilityHidden(true)
                }.font(.caption).foregroundStyle(theme.neutrals.text2).padding(.horizontal, 12).padding(.bottom, 12)
            }
            ForEach(Array(session.activeSets.enumerated()), id: \.element.id) { index, set in
                if !(snapshot && session.editorField != nil && set.completed) &&
                    !(layout == .board && !showBoardWarmupRows && set.completed && set.kind == "warmup") {
                    if typeSize.isAccessibilitySize { accessibleSetRow(set, index: index).id(set.id) }
                    else { setRow(set, index: index).id(set.id) }
                }
            }
        }
    }

    private func setRow(_ set: StudioSet, index: Int) -> some View {
        let current = session.currentSet?.id == set.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(set.kind == "warmup" ? "W" : "\(index)").font(.subheadline.weight(.semibold)).monospacedDigit()
                if current { Text(studioText("set.current")).font(.system(size: statusLabelSize, weight: .semibold)) }
            }.frame(width: 40, alignment: .leading)
                .foregroundStyle(current ? theme.primary.primaryText : theme.neutrals.text2)
            Text(index == 0 ? "40 × 12" : "60 × 10")
                .font(.caption).monospacedDigit().foregroundStyle(theme.neutrals.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
            numericField(set.weight.formatted(.number.precision(.fractionLength(0...1))), width: 60, active: current, field: "weight") {
                if current { session.beginEditing("weight") }
            }
            numericField("\(set.reps)", width: 48, active: current, field: "reps") {
                if current { session.beginEditing("reps") }
            }
            Button { session.complete(set.id) } label: {
                VStack(spacing: 2) {
                    Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: set.completed ? 20 : 24, weight: .regular))
                    if set.completed {
                        Text(studioText("set.doneShort")).font(.system(size: statusLabelSize, weight: .medium)).lineLimit(1)
                    }
                }.foregroundStyle(set.completed ? theme.success : theme.neutrals.text2)
                    .frame(width: 44, height: 56)
            }.buttonStyle(.plain)
                .accessibilityLabel(studioText(set.completed ? "set.uncomplete" : "set.complete") + " \(index + 1)")
        }
        .padding(.horizontal, 12).padding(.vertical, layout == .board ? 2 : 4)
        .background(current ? theme.primary.primarySubtle : (set.completed ? Color.clear : theme.neutrals.card))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? theme.primary.primaryBorder : .clear, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(studioText("set.number") + " \(index + 1)")
        .contextMenu {
            Button(studioText("set.delete"), role: .destructive) { session.deleteSet(set.id) }
                .disabled(session.activeSets.count <= 1)
        }
    }

    private func accessibleSetRow(_ set: StudioSet, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(studioText("set.number") + " \(index + 1) · " + studioText("set.\(set.kind)"))
                .font(.headline)
            Text(set.weight.formatted(.number.precision(.fractionLength(0...1))) + " kg × \(set.reps)")
                .font(.title2).monospacedDigit()
            HStack {
                if session.currentSet?.id == set.id {
                    Button(studioText("editor.weight")) { session.beginEditing("weight") }.frame(minHeight: 44)
                    Button(studioText("editor.reps")) { session.beginEditing("reps") }.frame(minHeight: 44)
                }
                Spacer()
                Button(studioText(set.completed ? "set.uncomplete" : "set.complete")) { session.complete(set.id) }
                    .frame(minHeight: 44)
            }.font(.body).buttonStyle(.plain).foregroundStyle(theme.primary.primaryText)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(StudioSurface(style: style, emphasized: session.currentSet?.id == set.id))
            .padding(.bottom, 12)
    }

    @ViewBuilder private func numericField(_ value: String, width: CGFloat, active: Bool, field: String, action: @escaping () -> Void) -> some View {
        if active {
            Button(action: action) {
                Text(value).font(.system(.body, design: .rounded, weight: .bold)).monospacedDigit()
                    .frame(width: width, height: 56)
                    .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).accessibilityLabel(studioText("editor.\(field)")).accessibilityValue(value)
        } else {
            Text(value).font(.system(.body, design: .rounded, weight: active ? .bold : .medium)).monospacedDigit()
                .frame(width: width, height: 56)
                .accessibilityLabel(studioText("editor.\(field)") + " " + value)
        }
    }

    private var addSetButton: some View {
        Button { session.addSet() } label: {
            Label(studioText("workout.addSet"), systemImage: "plus")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(theme.primary.primaryText)
                .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private var nextExerciseCard: some View {
        Button {
            let index = session.workoutIDs.firstIndex(of: session.activeExerciseID) ?? 0
            session.activeExerciseID = session.workoutIDs[(index + 1) % max(1, session.workoutIDs.count)]
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(studioText("workout.next")).font(.caption).foregroundStyle(theme.neutrals.text2)
                    let index = session.workoutIDs.firstIndex(of: session.activeExerciseID) ?? 0
                    let next = session.workoutIDs[(index + 1) % max(1, session.workoutIDs.count)]
                    Text(studioText("exercise.\(next)")).font(.body.weight(.semibold))
                }
                Spacer()
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }.padding(16).modifier(StudioSurface(style: style))
        }.buttonStyle(.plain)
    }

    private var focusWorkout: some View {
        VStack(alignment: .leading, spacing: 20) {
            exerciseHeading
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(studioText("set.working")).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\((session.activeSets.firstIndex(where: { !$0.completed }) ?? session.activeSets.count - 1) + 1) / \(session.activeSets.count)")
                        .font(.subheadline).monospacedDigit().foregroundStyle(theme.neutrals.text2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    focusNumber(field: "weight", value: session.currentSet?.weight.formatted(.number.precision(.fractionLength(0...1))) ?? "—", unit: "kg")
                    Text("×").font(.title).foregroundStyle(theme.neutrals.text2)
                    focusNumber(field: "reps", value: session.currentSet.map { String($0.reps) } ?? "—", unit: studioText("set.reps"))
                }
                HStack(spacing: 8) {
                    ForEach(session.activeSets) { set in
                        Capsule().fill(set.completed ? theme.primary.primary : theme.neutrals.border).frame(height: 4)
                    }
                }.accessibilityHidden(true)
            }.padding(20).modifier(StudioSurface(style: style, emphasized: true))
            HStack(spacing: 12) {
                adjustmentButton("−2.5", label: studioText("set.decreaseWeight")) { session.adjustWeight(-2.5) }
                Text(studioText("set.weight")).font(.caption).foregroundStyle(theme.neutrals.text2)
                adjustmentButton("+2.5", label: studioText("set.increaseWeight")) { session.adjustWeight(2.5) }
                Spacer()
                adjustmentButton("−1", label: studioText("set.decreaseReps")) { session.adjustReps(-1) }
                adjustmentButton("+1", label: studioText("set.increaseReps")) { session.adjustReps(1) }
            }
            HStack {
                Text(studioText("set.completed")).font(.subheadline.weight(.semibold))
                Spacer()
                Text(session.activeSets.filter(\.completed).map { $0.weight.formatted() + "×" + String($0.reps) }.joined(separator: "  ·  "))
                    .font(.caption).monospacedDigit().foregroundStyle(theme.neutrals.text2)
            }
            nextExerciseCard
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }

    private func focusNumber(field: String, value: String, unit: String) -> some View {
        Button { session.beginEditing(field) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.system(size: focusNumberSize, weight: .bold, design: style == .graphite ? .default : .rounded)).monospacedDigit()
                HStack(spacing: 4) {
                    Text(unit)
                    Image(systemName: "pencil").font(.caption2).accessibilityHidden(true)
                }.font(.subheadline).foregroundStyle(theme.neutrals.text2)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(studioText("editor.\(field)") + " " + value + " " + unit)
    }

    private func adjustmentButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(.subheadline, weight: .semibold)).monospacedDigit()
                .frame(minWidth: 48, minHeight: 44)
                .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var boardWorkout: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(studioText("workout.plan"), trailing: "\(session.workoutIDs.count) " + studioText("picker.results"))
            ForEach(Array(session.workoutIDs.enumerated()), id: \.element) { index, id in
                VStack(alignment: .leading, spacing: 8) {
                    Button { session.activeExerciseID = id } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(.system(.title3, design: .rounded, weight: .bold))
                                .monospacedDigit().foregroundStyle(theme.neutrals.text2).frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(studioText("exercise.\(id)")).font(.body.weight(.semibold))
                                let items = session.setsByExercise[id] ?? []
                                Text("\(items.filter(\.completed).count)/\(items.count) " + studioText("workout.setUnit") +
                                     (id == session.activeExerciseID ? " · " + studioText("set.includesWarmup") : ""))
                                    .font(.caption).foregroundStyle(theme.neutrals.text2).monospacedDigit()
                            }
                            Spacer(minLength: 0)
                            Image(systemName: session.activeExerciseID == id ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold)).accessibilityHidden(true)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if session.activeExerciseID == id {
                        setTable
                        HStack(spacing: 12) {
                            Button(studioText(showBoardWarmupRows ? "set.hideWarmup" : "set.showWarmup")) { showBoardWarmupRows.toggle() }
                                .font(.caption.weight(.medium)).frame(minWidth: 64, minHeight: 44)
                                .buttonStyle(.plain).foregroundStyle(theme.neutrals.text2)
                            addSetButton
                        }
                    }
                }
                .padding(12)
                .modifier(StudioSurface(style: style, emphasized: session.activeExerciseID == id))
            }
            Button { session.screen = .picker } label: {
                Label(studioText("workout.addExercise"), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.plain).foregroundStyle(theme.primary.primaryText)
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }

    @ViewBuilder private var bottomDock: some View {
        VStack(spacing: 12) {
            if let notice = session.notice {
                HStack {
                    Text(notice).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    StudioIconButton(symbol: "xmark", label: studioText("action.dismiss")) { session.notice = nil }
                }.padding(12).modifier(StudioSurface(style: style))
            }
            if session.screen == .picker {
                selectionDock
            } else {
                if session.deletedSet != nil {
                    HStack {
                        Image(systemName: "arrow.uturn.backward").accessibilityHidden(true)
                        Text(studioText("set.deleted")).font(.subheadline)
                        Spacer()
                        Button(studioText("action.undo")) { session.undoDelete() }
                            .font(.body.weight(.semibold)).frame(minHeight: 44).buttonStyle(.plain)
                    }.padding(.horizontal, 16).modifier(StudioSurface(style: style))
                } else { StudioRestPanel(session: session, style: style) }
                if session.editorField != nil {
                    StudioNumericEditor(session: session, style: style)
                } else if session.restEnd == nil {
                    StudioAction(title: studioText(session.currentSet == nil ? "workout.next" : "set.complete"),
                                 symbol: session.currentSet == nil ? "arrow.right" : "checkmark", style: style) {
                        if session.currentSet == nil {
                            let index = session.workoutIDs.firstIndex(of: session.activeExerciseID) ?? 0
                            session.activeExerciseID = session.workoutIDs[(index + 1) % max(1, session.workoutIDs.count)]
                        } else { session.complete() }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
        .background(theme.neutrals.bg)
        .overlay(alignment: .top) { theme.neutrals.border.frame(height: 0.5) }
    }

    private var selectionDock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showSelection = true } label: {
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle().fill(theme.primary.primarySubtle).frame(width: 32, height: 32)
                        Text("\(session.selectedIDs.count)").font(.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(theme.primary.primaryText)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(studioText("picker.selectionTitle")).font(.caption).foregroundStyle(theme.neutrals.text2)
                        Text(session.selectedIDs.isEmpty ? studioText("picker.selectionEmpty") :
                                session.selectedIDs.map { studioText("exercise.short.\($0)") }.joined(separator: " → "))
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            StudioAction(title: studioText("picker.add") + " · \(session.selectedIDs.count)", symbol: "arrow.right", style: style,
                         disabled: session.selectedIDs.isEmpty || session.replacementID != nil) { session.confirmSelection() }
        }
    }

    private var selectionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(studioText("picker.selectionTitle")).font(.title2.bold())
                Spacer()
                StudioIconButton(symbol: "xmark", label: studioText("action.dismiss")) { showSelection = false }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(session.selectedIDs, id: \.self) { id in
                        HStack {
                            Text("\((session.selectedIDs.firstIndex(of: id) ?? 0) + 1)").monospacedDigit()
                            Text(studioText("exercise.\(id)")).font(.body.weight(.medium))
                            Spacer()
                            StudioIconButton(symbol: "minus.circle", label: studioText("picker.remove")) { session.toggleSelection(id) }
                        }.frame(minHeight: 56)
                    }
                }
            }
            StudioAction(title: studioText("action.done"), symbol: "checkmark", style: style) { showSelection = false }
        }.padding(24).frame(minWidth: 330, minHeight: 360)
            .background(theme.neutrals.bg).foregroundStyle(theme.neutrals.text1)
    }

    private var finishedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundStyle(theme.primary.primaryText).accessibilityHidden(true)
            title(studioText("finish.success"), subtitle: studioText("finish.demoNote"))
            StudioSessionBand(session: session, style: style)
            Spacer()
            StudioAction(title: studioText("finish.restart"), symbol: "arrow.counterclockwise", style: style) {
                session.isFinished = false; session.screen = .picker
            }
        }.padding(24)
    }
}

#Preview("Tide · Flow · Light") {
    WorkoutStudioView(session: StudioSession(), style: .tide, layout: .flow)
        .environment(\.theme, StudioStyle.tide.theme(dark: false)).frame(width: 393, height: 852)
}

#Preview("Graphite · Focus · Dark") {
    WorkoutStudioView(session: StudioSession(screen: .workout), style: .graphite, layout: .focus)
        .environment(\.theme, StudioStyle.graphite.theme(dark: true)).environment(\.colorScheme, .dark)
        .frame(width: 393, height: 852)
}
