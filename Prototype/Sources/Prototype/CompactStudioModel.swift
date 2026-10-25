import Foundation
import Observation

public enum CompactLayout: String, CaseIterable, Identifiable, Sendable {
    case table, rail, matrix
    public var id: String { rawValue }
    public var title: String { studioText("compact.layout.\(rawValue)") }
}

public enum CompactAccessory: String, Sendable { case digits, rpe, type, weight }
public enum CompactOverlay: String, Sendable { case more, filters, selection, finish, advanced }
public enum CompactContentState: String, CaseIterable, Sendable {
    case populated, empty, loading, error
}

public struct CompactTarget: Equatable, Sendable {
    public let exerciseID: String
    public let setID: Int
}

/// Browsing is independent of the selected input target. Visibility callbacks
/// publish only section changes, never pixel offsets or draft mutations.
@Observable @MainActor
public final class CompactWorkoutNavigation {
    public private(set) var visibleExerciseID = "bench"
    public private(set) var jumpExerciseID = "bench"
    public private(set) var jumpRevision = 0

    public init() {}

    public func observeVisible(_ ids: [String], order: [String]) {
        guard let first = order.first(where: { ids.contains($0) }), first != visibleExerciseID else { return }
        visibleExerciseID = first
    }

    public func jump(to id: String, order: [String]) {
        guard order.contains(id) else { return }
        visibleExerciseID = id
        jumpExerciseID = id
        jumpRevision += 1
    }
}

/// UI-only fixture state. Advanced metadata remains separate from production models.
@Observable @MainActor
public final class CompactSession {
    public let core: StudioSession
    public let navigation = CompactWorkoutNavigation()
    public var contentState: CompactContentState = .populated
    public var forceReduceTransparency = false
    public var forceReduceMotion = false
    public var selectedSetID = 3
    public var overlay: CompactOverlay?
    public var accessory = CompactAccessory.digits
    public var notice: String?
    public private(set) var rpeByTarget: [String: Int] = [:]
    public private(set) var equipmentDefaults: [String: Double] = [:]
    public private(set) var isEditingEquipmentDefault = false
    public private(set) var equipmentDefaultText = ""
    public private(set) var defaultSelectAll = true
    private var defaultExerciseID: String?
    private var draftTarget: CompactTarget?
    private var draftRPE: Int?
    private var draftKind = "working"
    private var draftHasRPE = false

    public init(picker: Bool = false) {
        core = StudioSession(screen: picker ? .picker : .workout)
        if picker { core.selectedIDs = [] }
    }
    public func setContentState(_ state: CompactContentState) {
        contentState = state
    }
    public var target: CompactTarget { .init(exerciseID: core.activeExerciseID, setID: selectedSetID) }
    public var selectedSet: StudioSet? { core.activeSets.first { $0.id == selectedSetID } }
    public var selectedSetNumber: Int? { core.activeSets.firstIndex { $0.id == selectedSetID }.map { $0 + 1 } }
    private func key(_ target: CompactTarget) -> String { "\(target.exerciseID):\(target.setID)" }
    public func rpe(for target: CompactTarget) -> Int? { rpeByTarget[key(target)] }
    public var currentRPE: Int? { draftTarget == nil ? rpe(for: target) : (draftHasRPE ? draftRPE : nil) }
    public var currentKind: String { draftTarget == nil ? (selectedSet?.kind ?? "working") : draftKind }
    public var supportsEquipmentDefault: Bool { ["machine", "cable"].contains(core.activeExercise.equipment) }
    public var equipmentDefault: Double? { equipmentDefaults[core.activeExerciseID] }
    public var canSaveEquipmentDefault: Bool {
        guard let value = Double(equipmentDefaultText.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return false }
        return (0.0...999.99).contains(value)
    }

    public func beginEquipmentDefault() {
        guard supportsEquipmentDefault else { return }
        edit("weight")
        defaultExerciseID = core.activeExerciseID
        equipmentDefaultText = equipmentDefault.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        defaultSelectAll = true
        isEditingEquipmentDefault = true
        accessory = .digits
        overlay = nil
    }
    public func pressEquipmentDefaultKey(_ key: String) {
        guard isEditingEquipmentDefault else { return }
        if key == "delete" {
            if defaultSelectAll { equipmentDefaultText = "" }
            else if !equipmentDefaultText.isEmpty { equipmentDefaultText.removeLast() }
            defaultSelectAll = false
            return
        }
        guard key == "." || (key.count == 1 && key.first?.isNumber == true) else { return }
        var text = defaultSelectAll ? "" : equipmentDefaultText
        if key == "." {
            guard !text.contains(".") else { return }
            if text.isEmpty { text = "0" }
        } else if text == "0" { text = "" }
        if let point = text.firstIndex(of: "."), key != ".", text.distance(from: point, to: text.endIndex) > 2 { return }
        guard text.count < 6 else { return }
        equipmentDefaultText = text + key
        defaultSelectAll = false
    }
    public func selectEquipmentDefaultValue() {
        guard isEditingEquipmentDefault else { return }
        defaultSelectAll = true
    }
    public func saveEquipmentDefault() {
        guard isEditingEquipmentDefault, canSaveEquipmentDefault, let id = defaultExerciseID,
              let value = Double(equipmentDefaultText.replacingOccurrences(of: ",", with: ".")) else { return }
        equipmentDefaults[id] = value
        cancelEquipmentDefault()
        notice = studioText("weight.defaultSaved")
    }
    public func cancelEquipmentDefault() {
        isEditingEquipmentDefault = false
        defaultExerciseID = nil
    }
    public func clearEquipmentDefault() { equipmentDefaults[core.activeExerciseID] = nil }
    public func applyEquipmentDefault() {
        guard let value = equipmentDefault, !isEditingEquipmentDefault else { return }
        edit("weight")
        core.applyEditorTotalWeight(value)
        accessory = .digits
        overlay = nil
    }

    @discardableResult public func select(exercise: String, setID: Int? = nil) -> Bool {
        guard !isEditingEquipmentDefault else { return false }
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
        guard !isEditingEquipmentDefault, core.editorField != nil, core.editorCanCommit, let original = draftTarget,
              let index = core.setsByExercise[original.exerciseID]?.firstIndex(where: { $0.id == original.setID }) else { return }
        core.setsByExercise[original.exerciseID]?[index].kind = draftKind
        rpeByTarget[key(original)] = draftHasRPE ? draftRPE : nil
        core.commitEditor(completeSet: complete)
        draftTarget = nil
        accessory = .digits
        if complete { selectedSetID = core.currentSet?.id ?? original.setID }
    }
    public func discardDraft() {
        cancelEquipmentDefault()
        core.cancelEditor(); draftTarget = nil; accessory = .digits
    }
    public func completeSelected() {
        guard !isEditingEquipmentDefault else { return }
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
        guard !isEditingEquipmentDefault else { return }
        if core.editorField != nil {
            guard core.editorCanCommit else { return }; save()
        }
        core.addSet(); selectedSetID = core.activeSets.last?.id ?? selectedSetID
        if let value = equipmentDefault, let index = core.activeSets.indices.last {
            if core.activeSets[index].weightRight != nil {
                let left = (value * 50).rounded(.down) / 100
                core.setsByExercise[core.activeExerciseID]?[index].weight = left
                core.setsByExercise[core.activeExerciseID]?[index].weightRight = value - left
            } else { core.setsByExercise[core.activeExerciseID]?[index].weight = value }
        }
    }
    public func deleteSelected() {
        let id = selectedSetID
        discardDraft()
        core.deleteSet(id)
        selectedSetID = core.currentSet?.id ?? core.activeSets.first?.id ?? id
        overlay = nil
    }
    public func showPicker(replacing: Bool = false) {
        guard !isEditingEquipmentDefault else { return }
        guard core.editorField == nil || core.editorCanCommit else { return }
        if core.editorField != nil { save() }
        core.replacementID = replacing ? core.activeExerciseID : nil
        core.selectedIDs = []
        core.screen = .picker; overlay = nil
    }
    public func finish() {
        guard !isEditingEquipmentDefault else { return }
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
        sections = ["barbell", "dumbbell", "cable", "machine", "bodyweight"].compactMap { group in
            let items = results.filter { $0.equipment == group }
            return items.isEmpty ? nil : CompactPickerSection(id: group, items: items)
        }
        resultCount = results.count; committedKey = requestKey; generation += 1
    }
    public func reset() { query = ""; muscle = "all"; equipment = "all"; refresh() }
}
