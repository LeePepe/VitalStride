import DesignKit
import SwiftUI

/// B: independent scroll surfaces, one shared section navigator. Merely browsing
/// another section never changes the group bound to the keyboard or primary CTA.
struct CompactRailWorkout: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: CompactSession
    let snapshot: Bool

    var body: some View {
        ScrollViewReader { detailProxy in
            HStack(spacing: 0) {
                rail
                Rectangle().fill(theme.neutrals.border).frame(width: 1).accessibilityHidden(true)
                if snapshot {
                    // Export an explicit section landing, not a simulated drag.
                    GeometryReader { geometry in
                        VStack(spacing: 8) {
                            ForEach(snapshotIDs, id: \.self) { id in section(id) }
                        }.padding(.horizontal, 8).padding(.top, 8)
                            .frame(width: geometry.size.width).fixedSize(horizontal: false, vertical: true)
                            .frame(height: geometry.size.height, alignment: .top).clipped()
                    }
                } else {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: 0) {
                                LazyVStack(spacing: 8) {
                                    ForEach(session.core.workoutIDs, id: \.self) { id in section(id).id(id) }
                                }.scrollTargetLayout().padding(.horizontal, 8).padding(.top, 8)
                                // Let even the final section land at the top. This is
                                // viewport sizing, with no per-row geometry feedback.
                                Color.clear.frame(height: max(80, geometry.size.height - lastSectionMinHeight))
                            }
                        }.scrollIndicators(.visible)
                            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.1) { ids in
                                session.navigation.observeVisible(ids, order: session.core.workoutIDs)
                            }
                    }
                }
            }
            .onChange(of: session.navigation.jumpRevision) { _, _ in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    detailProxy.scrollTo(session.navigation.jumpExerciseID, anchor: .top)
                }
            }
            .onChange(of: session.core.editorField != nil) { _, editing in
                if editing {
                    detailProxy.scrollTo(rowID(session.core.activeExerciseID, session.selectedSetID), anchor: .center)
                }
            }
        }
    }

    private var lastSectionMinHeight: CGFloat {
        CGFloat((session.core.setsByExercise[session.core.workoutIDs.last ?? ""]?.count ?? 0) * 44 + 80)
    }

    private var snapshotIDs: [String] {
        let ids = session.core.workoutIDs
        let start = ids.firstIndex(of: session.navigation.visibleExerciseID) ?? 0
        return Array(ids.dropFirst(start))
    }

    private var rail: some View {
        ScrollViewReader { railProxy in
            Group {
                if snapshot { railItems.frame(maxHeight: .infinity, alignment: .top) }
                else { ScrollView { railItems }.scrollIndicators(.hidden) }
            }.frame(width: 64).background(theme.neutrals.inner.opacity(0.55))
                .onChange(of: session.navigation.visibleExerciseID) { _, id in
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0)) {
                        railProxy.scrollTo("rail-" + id, anchor: .center)
                    }
                }
        }
    }

    private var railItems: some View {
        VStack(spacing: 4) {
            ForEach(Array(session.core.workoutIDs.enumerated()), id: \.element) { index, id in
                let visible = session.navigation.visibleExerciseID == id
                let target = session.core.activeExerciseID == id
                let editing = (session.core.editorField != nil || session.isEditingEquipmentDefault) && target
                let sets = session.core.setsByExercise[id] ?? []
                Button {
                    if session.select(exercise: id) { session.navigation.jump(to: id, order: session.core.workoutIDs) }
                } label: {
                    CompactRailItem(index: index, id: id, visible: visible, editing: editing, sets: sets)
                }.buttonStyle(CompactPressStyle()).id("rail-" + id)
                    .accessibilityAddTraits(visible ? .isSelected : [])
                    .accessibilityLabel(studioText("exercise.short.\(id)") + " · \(sets.filter(\.completed).count)/\(sets.count)" + (visible ? " · " + studioText("compact.browse") : "") + (editing ? " · " + studioText("compact.editingShort") : ""))
            }

        }.padding(.horizontal, 4).padding(.vertical, 8)
    }

    private func section(_ id: String) -> some View {
        CompactRailSection(session: session, exerciseID: id)
    }
    private func rowID(_ exercise: String, _ set: Int) -> String { "group-\(exercise)-\(set)" }
}

private struct CompactRailItem: View {
    @Environment(\.theme) private var theme
    let index: Int
    let id: String
    let visible: Bool
    let editing: Bool
    let sets: [StudioSet]
    var body: some View {
        let indexText = String(index + 1)
        let exerciseText = studioText("exercise.short.\(id)")
        let completionText = "\(sets.filter(\.completed).count)/\(sets.count)"
        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(indexText).monospacedDigit()
                if editing {
                    Image(systemName: "pencil").font(.system(size: 14)).accessibilityHidden(true)
                    Text(studioText("compact.editingShort")).font(.system(size: 12))
                }
            }.font(.caption2).foregroundStyle(visible ? theme.neutrals.text1 : theme.neutrals.text2)
            Text(exerciseText).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            Text(completionText).font(.caption2).monospacedDigit().foregroundStyle(theme.neutrals.text2)
        }.frame(width: 56).frame(minHeight: 60)
            .padding(.vertical, 4)
            .background(visible ? theme.primary.primarySubtle : .clear, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                if visible { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(theme.primary.primaryBorder, lineWidth: 1) }
            }.contentShape(Rectangle())
    }
}

@MainActor
func compactSetActionTitle(session: CompactSession, editing: Bool) -> String {
    let key: String
    if editing { key = session.selectedSet?.completed == true ? "compact.saveEditsNumber" : "compact.saveLogNumber" }
    else { key = session.selectedSet?.completed == true ? "compact.uncompleteNumber" : "compact.completeNumber" }
    return String(format: studioText(key), session.selectedSetNumber.map(String.init) ?? "—")
}

private struct CompactRailSection: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    let exerciseID: String
    private var sets: [StudioSet] { session.core.setsByExercise[exerciseID] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(studioText("exercise.\(exerciseID)")).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(studioText("equipment.\(StudioExercise.fixtures.first { $0.id == exerciseID }?.equipment ?? "barbell")"))
                        .font(.caption2).foregroundStyle(theme.neutrals.text2)
                }
                Spacer(minLength: 0)
                Text("\(sets.filter(\.completed).count)/\(sets.count)")
                    .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(theme.neutrals.text2)
            }.padding(.horizontal, 12).frame(minHeight: 40)
            HStack(spacing: 4) {
                Text(studioText("set.number")).frame(width: 44)
                Text(studioText("set.weight") + " kg").frame(maxWidth: .infinity)
                Text(studioText("set.reps")).frame(width: 48)
                Text(studioText("compact.state")).frame(width: 44)
            }.font(.caption2).foregroundStyle(theme.neutrals.text2).padding(.horizontal, 12).frame(height: 24)
                .background(theme.neutrals.inner.opacity(0.65))
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                CompactSetRow(session: session, exerciseID: exerciseID, set: set, index: index, narrow: true)
                    .id("group-\(exerciseID)-\(set.id)")
            }
        }.padding(.bottom, 4)
            .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.neutrals.border.opacity(0.55), lineWidth: 0.5).allowsHitTesting(false) }
    }
}

/// Native Liquid Glass only on floating chrome; rows are opaque and inexpensive.
/// ImageRenderer cannot sample window backdrops. Its export uses an explicit
/// material approximation and edge highlight, labelled as such in the gallery.
struct CompactGlassSurface: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat
    let snapshot: Bool
    var enabled = true

    @ViewBuilder func body(content: Content) -> some View {
        if !enabled { content }
        else if reduceTransparency {
            content.background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay { edge }
        } else if #available(iOS 26.0, macOS 26.0, *), !snapshot {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
                .background(theme.neutrals.card.opacity(0.84), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay { edge }
                .compositingGroup()
                .shadow(color: .black.opacity(theme.isDark ? 0.24 : 0.10), radius: 12, y: 4)
        }
    }
    private var edge: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(
            LinearGradient(colors: [.white.opacity(theme.isDark ? 0.22 : 0.85), theme.neutrals.border.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75
        ).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CompactSnackbar: View {
    @Environment(\.theme) private var theme
    let session: CompactSession
    let snapshot: Bool

    var body: some View {
        if session.core.deletedSet != nil || session.core.restEnd != nil || session.notice != nil {
            HStack(spacing: 8) {
                if let deleted = session.core.deletedSet {
                    Image(systemName: "trash").foregroundStyle(theme.neutrals.text2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: studioText("compact.deletedTarget"), studioText("exercise.short.\(deleted.0)"), String(deleted.1 + 1)))
                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if let end = session.core.restEnd {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let seconds = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                                Text(studioText("compact.restContinues") + " · " + String(format: "%d:%02d", seconds / 60, seconds % 60))
                                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(theme.neutrals.text2)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    action("action.undo") { session.core.undoDelete() }
                } else if let end = session.core.restEnd {
                    Image(systemName: "timer").foregroundStyle(theme.primary.primaryText).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(studioText("compact.resting")).font(.caption2).foregroundStyle(theme.neutrals.text2)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                            Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                    action("rest.minusShort") { session.core.adjustRest(-10) }
                    action("rest.plusShort") { session.core.adjustRest(10) }
                    action("rest.skip") { session.core.restEnd = nil }
                } else {
                    Text(session.notice ?? "").font(.caption)
                    Spacer(minLength: 0)
                    Button { session.notice = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(studioText("action.dismiss"))
                }
            }.padding(.horizontal, 12).frame(height: 60)
                .modifier(CompactGlassSurface(radius: 22, snapshot: snapshot))
                .accessibilityElement(children: .contain)
        }
    }
    private func action(_ key: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(studioText(key)).font(.caption.weight(.semibold)).foregroundStyle(theme.primary.primaryText)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
