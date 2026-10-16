import Foundation
import Observation

public enum CompactLayout: String, CaseIterable, Identifiable, Sendable {
    case table, rail, matrix
    public var id: String { rawValue }
    public var title: String { studioText("compact.layout.\(rawValue)") }
}

public enum CompactAccessory: String, Sendable { case digits, rpe, type }
public enum CompactOverlay: String, Sendable { case more, filters, selection, finish, advanced }

public struct CompactTarget: Equatable, Sendable {
    public let exerciseID: String
    public let setID: Int
}

/// UI-only fixture state. Advanced metadata remains separate from production models.
@Observable @MainActor
public final class CompactSession {
    public let core: StudioSession
    public var selectedSetID = 3
    public var overlay: CompactOverlay?
    public var accessory = CompactAccessory.digits
    public var notice: String?
    public private(set) var rpeByTarget: [String: Int] = [:]
    private var draftTarget: CompactTarget?
    private var draftRPE: Int?
    private var draftKind = "working"
    private var draftHasRPE = false

    public init(picker: Bool = false) {
        core = StudioSession(screen: picker ? .picker : .workout)
        if picker { core.selectedIDs = [] }
    }
    public var target: CompactTarget { .init(exerciseID: core.activeExerciseID, setID: selectedSetID) }
    public var selectedSet: StudioSet? { core.activeSets.first { $0.id == selectedSetID } }
    public var selectedSetNumber: Int? { core.activeSets.firstIndex { $0.id == selectedSetID }.map { $0 + 1 } }
    private func key(_ target: CompactTarget) -> String { "\(target.exerciseID):\(target.setID)" }
    public func rpe(for target: CompactTarget) -> Int? { rpeByTarget[key(target)] }
    public var currentRPE: Int? { draftTarget == nil ? rpe(for: target) : (draftHasRPE ? draftRPE : nil) }
    public var currentKind: String { draftTarget == nil ? (selectedSet?.kind ?? "working") : draftKind }

    @discardableResult public func select(exercise: String, setID: Int? = nil) -> Bool {
        if exercise == core.activeExerciseID && (setID == nil || setID == selectedSetID) { return true }
        if let setID, core.setsByExercise[exercise]?.contains(where: { $0.id == setID }) != true { return false }
        if core.editorField != nil {
            guard core.editorCanCommit else { return false }
            save()
        }
        guard let sets = core.setsByExercise[exercise], !sets.isEmpty else { return false }
        core.activeExerciseID = exercise
        selectedSetID = setID ?? sets.first(where: { !$0.completed })?.id ?? sets[0].id
        return true
    }
    public func edit(_ field: String) {
        if core.editorField != nil { core.switchEditor(to: field); return }
        guard selectedSet != nil else { return }
        draftTarget = target
        draftKind = selectedSet?.kind ?? "working"
        draftRPE = rpe(for: target)
        draftHasRPE = draftRPE != nil
        core.beginEditing(field, setID: selectedSetID)
        accessory = .digits
    }
    public func setRPE(_ value: Int?) {
        guard value == nil || (6...10).contains(value ?? 0) else { return }
        if draftTarget != nil { draftRPE = value; draftHasRPE = value != nil }
        else { rpeByTarget[key(target)] = value }
    }
    public func setKind(_ kind: String) {
        guard ["working", "warmup"].contains(kind) else { return }
        if draftTarget != nil { draftKind = kind }
        else if let index = core.activeSets.firstIndex(where: { $0.id == selectedSetID }) {
            core.setsByExercise[core.activeExerciseID]?[index].kind = kind
        }
    }
    public func save(complete: Bool = false) {
        guard core.editorField != nil, core.editorCanCommit, let original = draftTarget,
              let index = core.setsByExercise[original.exerciseID]?.firstIndex(where: { $0.id == original.setID }) else { return }
        core.setsByExercise[original.exerciseID]?[index].kind = draftKind
        rpeByTarget[key(original)] = draftHasRPE ? draftRPE : nil
        core.commitEditor(completeSet: complete)
        draftTarget = nil
        accessory = .digits
        if complete { selectedSetID = core.currentSet?.id ?? original.setID }
    }
    public func discardDraft() {
        core.cancelEditor(); draftTarget = nil; accessory = .digits
    }
    public func completeSelected() {
        if core.editorField != nil {
            guard core.editorCanCommit else { return }
            let wasCompleted = selectedSet?.completed == true
            save(complete: !wasCompleted)
            if wasCompleted { core.complete(selectedSetID) }
            return
        }
        guard let selectedSet else { return }
        core.complete(selectedSet.id)
        if !selectedSet.completed { selectedSetID = core.currentSet?.id ?? selectedSet.id }
    }
    public func addSet() {
        if core.editorField != nil {
            guard core.editorCanCommit else { return }; save()
        }
        core.addSet(); selectedSetID = core.activeSets.last?.id ?? selectedSetID
    }
    public func deleteSelected() {
        let id = selectedSetID
        discardDraft()
        core.deleteSet(id)
        selectedSetID = core.currentSet?.id ?? core.activeSets.first?.id ?? id
        overlay = nil
    }
    public func showPicker(replacing: Bool = false) {
        guard core.editorField == nil || core.editorCanCommit else { return }
        if core.editorField != nil { save() }
        core.replacementID = replacing ? core.activeExerciseID : nil
        core.selectedIDs = []
        core.screen = .picker; overlay = nil
    }
    public func finish() {
        if core.editorField != nil {
            guard core.editorCanCommit else { return }; save()
        }
        core.isFinished = true; core.restEnd = nil; core.deletedSet = nil; overlay = nil
    }
}

public struct CompactPickerSection: Identifiable, Sendable, Equatable {
    public let id: String
    public let items: [StudioExercise]
}

/// Cached query output. Only query/filter changes rebuild the sections; selection is independent.
@Observable @MainActor
public final class CompactPickerModel {
    public var query = ""
    public var muscle = "all"
    public var equipment = "all"
    public private(set) var sections: [CompactPickerSection] = []
    public private(set) var resultCount = 0
    public private(set) var generation = 0
    private var committedKey: String?
    public init() { refresh() }
    public var requestKey: String { query + "\u{1F}" + muscle + "\u{1F}" + equipment }
    public func refresh() {
        guard committedKey != requestKey else { return }
        let results = StudioExercise.search(StudioExercise.fixtures, query: query, muscle: muscle, equipment: equipment)
        sections = ["barbell", "dumbbell", "cable", "bodyweight"].compactMap { group in
            let items = results.filter { $0.equipment == group }
            return items.isEmpty ? nil : CompactPickerSection(id: group, items: items)
        }
        resultCount = results.count; committedKey = requestKey; generation += 1
    }
    public func reset() { query = ""; muscle = "all"; equipment = "all"; refresh() }
}
