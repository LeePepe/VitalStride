import DesignKit
import Foundation
import Observation
import SwiftUI

/// Native, fixture-only exploration. Never reads or writes production data.
public enum StudioStyle: String, CaseIterable, Identifiable, Sendable {
    case tide, graphite, ember
    public var id: String { rawValue }
    public var title: String { studioText("style.\(rawValue)") }
    public var radius: CGFloat { self == .graphite ? 10 : (self == .ember ? 24 : 18) }
    public func theme(dark: Bool) -> Theme {
        Theme(seed: self == .tide ? .teal : (self == .ember ? .orange : .blue),
              neutral: self == .tide ? .slate : .neutral, isDark: dark)
    }
}

public enum StudioLayout: String, CaseIterable, Identifiable, Sendable {
    case flow, focus, board
    public var id: String { rawValue }
    public var title: String { studioText("layout.\(rawValue)") }
}

public enum StudioKeyboardLayout: String, CaseIterable, Identifiable, Sendable {
    case grid, thumb, sequence
    public var id: String { rawValue }
    public var title: String { studioText("keyboard.layout.\(rawValue)") }
    public var pairedLayout: StudioLayout {
        switch self { case .grid: .flow; case .thumb: .focus; case .sequence: .board }
    }
}

public enum StudioScreen: String, CaseIterable, Identifiable, Sendable {
    case picker, workout
    public var id: String { rawValue }
    public var title: String { studioText("screen.\(rawValue)") }
}

public enum StudioScenario: String, CaseIterable, Sendable {
    case normal, noResults, emptyLibrary, resting, undo, keyboard, finished
}

public func studioText(_ key: String) -> String {
    let systemValue = NSLocalizedString(key, tableName: "Studio", bundle: StudioCatalog.bundle,
                                      comment: "Workout design exploration")
    return StudioCatalog.values[key] ?? systemValue
}

// Support both Xcode's compiled catalog and SwiftPM versions that copy the catalog.
// There is only one checked-in translation source, never a .strings duplicate.
private enum StudioCatalog {
    struct Catalog: Decodable { let strings: [String: Entry] }
    struct Entry: Decodable { let localizations: [String: Localization] }
    struct Localization: Decodable { let stringUnit: Unit }
    struct Unit: Decodable { let value: String }
    static let language = ProcessInfo.processInfo.environment["STUDIO_LANGUAGE"] ?? "zh-Hans"
    static let bundle: Bundle = {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return Bundle.module }
        return localizedBundle
    }()
    static let values: [String: String] = {
        guard let url = Bundle.module.url(forResource: "Studio", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [:] }
        return catalog.strings.mapValues { $0.localizations[language]?.stringUnit.value ?? $0.localizations["en"]?.stringUnit.value ?? "" }
    }()
}

public struct StudioExercise: Identifiable, Sendable, Equatable {
    public let id: String
    public let muscle: String
    public let equipment: String
    public let symbol: String
    public let aliases: String
    public var name: String { studioText("exercise.\(id)") }
    public var detail: String { studioText("muscle.\(muscle)") + " · " + studioText("equipment.\(equipment)") }

    public static let fixtures: [StudioExercise] = [
        .init(id: "bench", muscle: "chest", equipment: "barbell", symbol: "dumbbell", aliases: "barbell bench press 杠铃卧推 胸"),
        .init(id: "incline", muscle: "chest", equipment: "dumbbell", symbol: "dumbbell", aliases: "incline dumbbell press 上斜哑铃卧推 胸"),
        .init(id: "fly", muscle: "chest", equipment: "cable", symbol: "figure.strengthtraining.functional", aliases: "cable fly 绳索夹胸 胸"),
        .init(id: "press", muscle: "shoulders", equipment: "dumbbell", symbol: "dumbbell", aliases: "seated shoulder press 坐姿哑铃推举 肩"),
        .init(id: "row", muscle: "back", equipment: "barbell", symbol: "dumbbell", aliases: "barbell row 杠铃划船 背"),
        .init(id: "squat", muscle: "legs", equipment: "barbell", symbol: "figure.strengthtraining.traditional", aliases: "barbell back squat 杠铃深蹲 腿"),
        .init(id: "pulldown", muscle: "back", equipment: "cable", symbol: "figure.strengthtraining.functional", aliases: "lat pulldown 高位下拉 背"),
        .init(id: "curl", muscle: "arms", equipment: "dumbbell", symbol: "dumbbell", aliases: "dumbbell curl 哑铃弯举 手臂"),
        .init(id: "pushup", muscle: "chest", equipment: "bodyweight", symbol: "figure.strengthtraining.functional", aliases: "push up pushup 俯卧撑 胸"),
        .init(id: "plank", muscle: "core", equipment: "bodyweight", symbol: "figure.core.training", aliases: "plank 平板支撑 核心"),
        .init(id: "machinepress", muscle: "chest", equipment: "machine", symbol: "dumbbell", aliases: "machine chest press 器械胸推 固定器械 胸")
    ]

    public static func search(_ items: [Self], query: String, muscle: String, equipment: String) -> [Self] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let terms = normalized.split(separator: " ")
        return items.filter { item in
            (muscle == "all" || item.muscle == muscle) &&
            (equipment == "all" || item.equipment == equipment) &&
            terms.allSatisfy { item.aliases.localizedStandardContains($0) || item.name.localizedStandardContains($0) }
        }
    }
}

public struct StudioSet: Identifiable, Sendable, Equatable {
    public let id: Int
    public var weight: Double
    public var reps: Int
    public var completed: Bool
    public var kind: String
    public var weightRight: Double? = nil
}

@Observable @MainActor
public final class StudioSession {
    public var screen: StudioScreen
    public var query = ""
    public var muscle = "all"
    public var equipment = "all"
    public var selectedIDs = ["bench", "incline"]
    public var workoutIDs = ["bench", "incline", "fly", "press"]
    public var activeExerciseID = "bench"
    public var setsByExercise: [String: [StudioSet]] = [:]
    public var restEnd: Date?
    public var restTotal: TimeInterval = 90
    public var deletedSet: (String, Int, StudioSet)?
    public var editorField: String?
    public var editorValue = ""
    public var editorSelectAll = true
    public var keyboardLeftHanded = false
    private var editorValues: [String: String] = [:]
    private var editorExerciseID: String?
    private var editorSetID: Int?
    private var splitDraft: (left: Double, right: Double)?
    public var notice: String?
    public var replacementID: String?
    public var isFinished = false
    public var emptyLibrary = false
    private var nextSetID = 100

    public init(screen: StudioScreen = .picker, scenario: StudioScenario = .normal) {
        self.screen = screen
        for id in workoutIDs {
            setsByExercise[id] = [
                .init(id: 1, weight: id == "bench" ? 40 : 24, reps: 12, completed: id == "bench", kind: "warmup"),
                .init(id: 2, weight: id == "bench" ? 60 : 24, reps: 10, completed: id == "bench", kind: "working"),
                .init(id: 3, weight: id == "bench" ? 60 : 24, reps: 10, completed: false, kind: "working"),
                .init(id: 4, weight: id == "bench" ? 60 : 24, reps: 8, completed: false, kind: "working")
            ]
        }
        switch scenario {
        case .noResults: query = "zzzz"
        case .emptyLibrary: emptyLibrary = true; selectedIDs = []
        case .resting: restEnd = Date().addingTimeInterval(74)
        case .undo: deleteSet(4)
        case .keyboard: beginEditing("weight")
        case .finished: isFinished = true
        case .normal: break
        }
    }

    public var results: [StudioExercise] {
        emptyLibrary ? [] : StudioExercise.search(StudioExercise.fixtures, query: query, muscle: muscle, equipment: equipment)
    }
    public var activeExercise: StudioExercise {
        StudioExercise.fixtures.first { $0.id == activeExerciseID } ?? StudioExercise.fixtures[0]
    }
    public var activeSets: [StudioSet] { setsByExercise[activeExerciseID] ?? [] }
    public var currentSet: StudioSet? { activeSets.first { !$0.completed } }
    public var completedCount: Int { setsByExercise.values.flatMap { $0 }.filter(\.completed).count }
    public var totalCount: Int { setsByExercise.values.reduce(0) { $0 + $1.count } }
    public var totalVolume: Double {
        setsByExercise.values.flatMap { $0 }.filter(\.completed).reduce(0) { $0 + ($1.weight + ($1.weightRight ?? 0)) * Double($1.reps) }
    }

    public func toggleSelection(_ id: String) {
        if let replacementID {
            if let index = workoutIDs.firstIndex(of: replacementID), !workoutIDs.contains(id) {
                workoutIDs[index] = id
                setsByExercise[id] = setsByExercise.removeValue(forKey: replacementID)
                activeExerciseID = id
            }
            self.replacementID = nil
            screen = .workout
        } else if selectedIDs.contains(id) {
            selectedIDs.removeAll { $0 == id }
        } else {
            selectedIDs.append(id)
        }
    }

    public func confirmSelection() {
        for id in selectedIDs where !workoutIDs.contains(id) {
            workoutIDs.append(id)
            setsByExercise[id] = [.init(id: 1, weight: 20, reps: 10, completed: false, kind: "working")]
        }
        screen = .workout
    }

    public func clearFilters() { query = ""; muscle = "all"; equipment = "all" }
    public func adjustWeight(_ amount: Double) {
        guard let currentSet else { return }
        updateSet(currentSet.id) { $0.weight = max(0, $0.weight + amount) }
    }
    public func adjustReps(_ amount: Int) {
        guard let currentSet else { return }
        updateSet(currentSet.id) { $0.reps = max(1, $0.reps + amount) }
    }
    public func complete(_ id: Int? = nil) {
        guard let target = id ?? currentSet?.id else { return }
        var nowCompleted = false
        updateSet(target) { $0.completed.toggle(); nowCompleted = $0.completed }
        restEnd = nowCompleted ? Date().addingTimeInterval(restTotal) : nil
    }
    public func addSet() {
        let previous = activeSets.last
        setsByExercise[activeExerciseID, default: []].append(
            .init(id: nextSetID, weight: previous?.weight ?? 20, reps: previous?.reps ?? 10, completed: false, kind: "working", weightRight: previous?.weightRight))
        nextSetID += 1
    }
    public func deleteSet(_ id: Int) {
        guard activeSets.count > 1, let index = activeSets.firstIndex(where: { $0.id == id }) else { return }
        if editorExerciseID == activeExerciseID && editorSetID == id { cancelEditor() }
        deletedSet = (activeExerciseID, index, activeSets[index])
        setsByExercise[activeExerciseID]?.remove(at: index)
    }
    public func undoDelete() {
        guard let (exerciseID, index, item) = deletedSet else { return }
        setsByExercise[exerciseID, default: []].insert(item, at: min(index, setsByExercise[exerciseID, default: []].count))
        deletedSet = nil
    }
    public func adjustRest(_ seconds: TimeInterval) {
        guard let restEnd else { return }
        self.restEnd = max(Date(), restEnd.addingTimeInterval(seconds))
        restTotal = max(restTotal, self.restEnd?.timeIntervalSinceNow ?? 0)
    }
    public func beginEditing(_ field: String, setID: Int? = nil) {
        let target = setID.flatMap { id in activeSets.first { $0.id == id } } ?? (setID == nil ? currentSet : nil)
        guard let currentSet = target else { return }
        notice = nil
        editorExerciseID = activeExerciseID
        editorSetID = currentSet.id
        editorValues = ["weight": currentSet.weight.formatted(.number.precision(.fractionLength(0...2))), "reps": String(currentSet.reps)]
        if let right = currentSet.weightRight { editorValues["weightRight"] = weightText(right) }
        splitDraft = nil
        editorField = field
        editorValue = editorValues[field] ?? ""
        editorSelectAll = true
    }
    public func switchEditor(to field: String) {
        guard let current = editorField, field != current else { return }
        editorValues[current] = editorValue
        editorField = field
        editorValue = editorValues[field] ?? ""
        editorSelectAll = true
    }
    public func pressEditorKey(_ key: String) {
        guard editorField != nil else { return }
        notice = nil
        if key == "delete" {
            if editorSelectAll { editorValue = "" }
            else if !editorValue.isEmpty { editorValue.removeLast() }
            editorSelectAll = false
            return
        }
        let decimal = key == "."
        guard (key.count == 1 && key.first?.isNumber == true) || decimal else { return }
        guard !decimal || editorField == "weight" || editorField == "weightRight" else { return }
        var next = editorSelectAll ? "" : editorValue
        if decimal {
            guard !next.contains(".") else { return }
            if next.isEmpty { next = "0" }
        } else if next == "0" { next = "" }
        if let point = next.firstIndex(of: "."), !decimal,
           next.distance(from: point, to: next.endIndex) > 2 { return }
        guard next.count < 6 else { return }
        editorValue = next + key
        editorSelectAll = false
    }
    private var mergedEditorValues: [String: String] {
        var values = editorValues
        if let field = editorField { values[field] = editorValue }
        return values
    }
    private func parsedDraft() -> (Double, Int, Double?)? {
        let values = mergedEditorValues
        guard let weight = Double((values["weight"] ?? "").replacingOccurrences(of: ",", with: ".")),
              let reps = Int(values["reps"] ?? ""), weight.isFinite,
              (0...999).contains(weight), (1...999).contains(reps) else { return nil }
        var right: Double?
        if let text = values["weightRight"] {
            guard let parsed = Double(text.replacingOccurrences(of: ",", with: ".")), parsed.isFinite,
                  (0...999).contains(parsed) else { return nil }
            right = parsed
        }
        return (weight, reps, right)
    }
    public var editorCanCommit: Bool { parsedDraft() != nil }
    public var editorWeightText: String { mergedEditorValues["weight"] ?? "—" }
    public var editorRightWeightText: String { mergedEditorValues["weightRight"] ?? "—" }
    public var editorIsSplit: Bool { mergedEditorValues["weightRight"] != nil }
    public var editorCanUseTotal: Bool {
        guard let (left, _, right) = parsedDraft() else { return false }
        return left + (right ?? 0) <= 999
    }
    public var editorRepsText: String { mergedEditorValues["reps"] ?? "—" }
    public var editorError: String? {
        guard editorField != nil, !editorCanCommit else { return nil }
        return studioText("keyboard.invalid")
    }
    public func adjustEditor(_ amount: Double) {
        guard let value = Double(editorValue.replacingOccurrences(of: ",", with: ".")) else { return }
        let adjusted = min(999, max(editorField == "reps" ? 1 : 0, value + amount))
        editorValue = editorField == "reps" ? String(Int(adjusted)) : adjusted.formatted(.number.precision(.fractionLength(0...2)))
        editorSelectAll = false
    }
    public func presetEditorReps(_ value: Int) {
        switchEditor(to: "reps")
        editorValue = String(value)
        editorSelectAll = true
    }
    public func usePreviousEditorValues() {
        let split = editorIsSplit
        let total: Double = editorExerciseID == "bench" ? 60 : 24
        editorValues = ["weight": weightText(split ? total / 2 : total), "reps": "10"]
        if split { editorValues["weightRight"] = weightText(total / 2) }
        splitDraft = nil
        editorValue = editorValues[editorField ?? "weight"] ?? ""
        editorSelectAll = true
    }
    public func copyEditorToNext() {
        guard let (weight, reps, right) = parsedDraft(), let exerciseID = editorExerciseID, let setID = editorSetID,
              let index = setsByExercise[exerciseID]?.firstIndex(where: { $0.id == setID }) else { return }
        if let items = setsByExercise[exerciseID], index + 1 < items.count {
            setsByExercise[exerciseID]?[index + 1].weight = weight
            setsByExercise[exerciseID]?[index + 1].reps = reps
            setsByExercise[exerciseID]?[index + 1].weightRight = right
        } else {
            setsByExercise[exerciseID, default: []].append(.init(id: nextSetID, weight: weight, reps: reps, completed: false, kind: "working", weightRight: right))
            nextSetID += 1
        }
        notice = studioText("keyboard.copied")
    }
    public func cancelEditor() {
        editorField = nil
        editorValues = [:]; editorExerciseID = nil; editorSetID = nil
        splitDraft = nil
    }
    public func commitEditor(completeSet: Bool = false) {
        guard let (weight, reps, right) = parsedDraft(), let exerciseID = editorExerciseID, let setID = editorSetID,
              let index = setsByExercise[exerciseID]?.firstIndex(where: { $0.id == setID }) else { return }
        setsByExercise[exerciseID]?[index].weight = weight
        setsByExercise[exerciseID]?[index].reps = reps
        setsByExercise[exerciseID]?[index].weightRight = right
        if completeSet {
            setsByExercise[exerciseID]?[index].completed = true
            restEnd = Date().addingTimeInterval(restTotal)
        }
        cancelEditor()
    }
    /// Convert only the current draft. Total load is preserved and an unequal
    /// pair survives an unchanged split → total → split round trip.
    public func setEditorSplit(_ split: Bool) {
        guard editorField != nil, split != editorIsSplit, let (left, _, right) = parsedDraft() else { return }
        editorValues = mergedEditorValues
        if split {
            let pair = splitDraft.flatMap { abs($0.left + $0.right - left) < 0.00001 ? $0 : nil }
            let half = (left * 50).rounded(.down) / 100
            editorValues["weight"] = weightText(pair?.left ?? half)
            editorValues["weightRight"] = weightText(pair?.right ?? (left - half))
        } else {
            guard let right, left + right <= 999 else { return }
            splitDraft = (left, right)
            editorValues["weight"] = weightText(left + right)
            editorValues["weightRight"] = nil
        }
        if editorField != "reps" { editorField = "weight" }
        editorValue = editorValues[editorField ?? "weight"] ?? ""
        editorSelectAll = true
    }
    public func matchEditorSides() {
        guard editorIsSplit, editorCanCommit else { return }
        editorValues = mergedEditorValues
        editorValues["weightRight"] = editorValues["weight"]
        editorValue = editorValues[editorField ?? "weight"] ?? ""
        editorSelectAll = true
    }
    public func swapEditorSides() {
        guard editorIsSplit, editorCanCommit else { return }
        let values = mergedEditorValues
        editorValues = values
        editorValues["weight"] = values["weightRight"]
        editorValues["weightRight"] = values["weight"]
        editorValue = editorValues[editorField ?? "weight"] ?? ""
        editorSelectAll = true
    }
    public func applyEditorTotalWeight(_ total: Double) {
        guard editorField != nil, total.isFinite, (0...999).contains(total) else { return }
        let split = editorIsSplit
        editorValues = mergedEditorValues
        let half = (total * 50).rounded(.down) / 100
        editorValues["weight"] = weightText(split ? half : total)
        if split { editorValues["weightRight"] = weightText(total - half) }
        splitDraft = nil
        editorValue = editorValues[editorField ?? "weight"] ?? ""
        editorSelectAll = true
    }
    private func weightText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
    private func updateSet(_ id: Int, _ update: (inout StudioSet) -> Void) {
        guard let index = setsByExercise[activeExerciseID]?.firstIndex(where: { $0.id == id }) else { return }
        update(&setsByExercise[activeExerciseID, default: []][index])
    }
}
