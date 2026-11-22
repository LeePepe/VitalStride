// swiftlint:disable no_hardcoded_chinese
import DesignKit
import Foundation
import SwiftUI

// MARK: - Speed, State, and Variant Metadata

/// Standard playback/animation speed multipliers for native 120Hz SwiftUI preview inspection.
public enum PreviewSpeedMultiplier: Double, CaseIterable, Identifiable, Codable, Sendable {
    case x1_0 = 1.0
    case x0_5 = 0.5
    case x0_35 = 0.35
    case x0_25 = 0.25

    public var id: Double { rawValue }

    public var label: String {
        switch self {
        case .x1_0: "1.0x"
        case .x0_5: "0.5x"
        case .x0_35: "0.35x"
        case .x0_25: "0.25x"
        }
    }

    public func scaledSpring(response: Double = 0.30, dampingFraction: Double = 0.90) -> Animation {
        let scale = max(0.1, 1.0 / max(0.1, rawValue))
        return .spring(response: response * scale, dampingFraction: dampingFraction)
    }
}

/// Unified 4-state switcher across all 4 Loop 8 redesigned pages.
public enum VitalStridePreviewDataState: String, CaseIterable, Identifiable, Codable, Sendable {
    case populated
    case empty
    case loading
    case error

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .populated: "Populated"
        case .empty: "Empty"
        case .loading: "Loading"
        case .error: "Error"
        }
    }

    public var holisticState: HolisticPreviewState {
        switch self {
        case .populated: .populated
        case .empty: .empty
        case .loading: .loading
        case .error: .error
        }
    }

    public var heartSleepState: HeartSleepCouplingPreviewState {
        switch self {
        case .populated: .populated
        case .empty: .empty
        case .loading: .loading
        case .error: .error
        }
    }

    public var workoutLoadState: WorkoutLoadProgressionPreviewState {
        switch self {
        case .populated: .populated
        case .empty: .empty
        case .loading: .loading
        case .error: .error
        }
    }

    public var stepsBodyState: StepsBodySettingsPreviewState {
        switch self {
        case .populated: .populated
        case .empty: .empty
        case .loading: .loading
        case .error: .error
        }
    }
}

/// Metadata and spring choreography parameters for a single `v01..v10` candidate.
public struct PreviewVariantDescriptor: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let badgeCode: String
    public let title: String
    public let summary: String
    public let baseSpringResponse: Double
    public let dampingFraction: Double

    public init(
        id: String,
        badgeCode: String? = nil,
        title: String,
        summary: String,
        baseSpringResponse: Double = 0.30,
        dampingFraction: Double = 0.90
    ) {
        self.id = id
        self.badgeCode = badgeCode ?? id.uppercased()
        self.title = title
        self.summary = summary
        self.baseSpringResponse = baseSpringResponse
        self.dampingFraction = dampingFraction
    }

    public func spring(for speed: PreviewSpeedMultiplier) -> Animation {
        speed.scaledSpring(response: baseSpringResponse, dampingFraction: dampingFraction)
    }
}

/// Selection / Star / Notes feedback state for a single candidate.
public struct PreviewVariantFeedback: Codable, Equatable, Sendable {
    public var variantID: String
    public var isSelected: Bool
    public var isStarred: Bool
    public var notes: String
    public var updatedAt: Date

    public init(
        variantID: String,
        isSelected: Bool = false,
        isStarred: Bool = false,
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.variantID = variantID
        self.isSelected = isSelected
        self.isStarred = isStarred
        self.notes = notes
        self.updatedAt = updatedAt
    }
}

/// Complete JSON receipt persisted to disk whenever the Owner interacts with SELECT / STAR / NOTES
/// in the native macOS 10-Up Preview Host.
public struct PreviewSelectionReceipt: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schema: Int
    public var selectedVariantID: String?
    public var starredVariantIDs: [String]
    public var notesByVariant: [String: String]
    public var variants: [String: PreviewVariantFeedback]
    public var speedMultiplier: Double
    public var appearance: String
    public var dataState: String
    public var allExpanded: Bool
    public var updatedAt: Date

    public init(
        schema: Int = PreviewSelectionReceipt.currentSchemaVersion,
        selectedVariantID: String? = nil,
        starredVariantIDs: [String] = [],
        notesByVariant: [String: String] = [:],
        variants: [String: PreviewVariantFeedback] = [:],
        speedMultiplier: Double = 1.0,
        appearance: String = "light",
        dataState: String = VitalStridePreviewDataState.populated.rawValue,
        allExpanded: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.schema = schema
        self.selectedVariantID = selectedVariantID
        self.starredVariantIDs = starredVariantIDs
        self.notesByVariant = notesByVariant
        self.variants = variants
        self.speedMultiplier = speedMultiplier
        self.appearance = appearance
        self.dataState = dataState
        self.allExpanded = allExpanded
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case round
        case selectedVariantID
        case starredVariantIDs
        case notesByVariant
        case variants
        case speedMultiplier
        case appearance
        case dataState
        case allExpanded
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchema = try container.decodeIfPresent(Int.self, forKey: .schema)
            ?? (try container.decodeIfPresent(Int.self, forKey: .round))
            ?? Self.currentSchemaVersion
        self.schema = decodedSchema
        if let rawSelected = try container.decodeIfPresent(String.self, forKey: .selectedVariantID) {
            let trimmed = rawSelected.trimmingCharacters(in: .whitespacesAndNewlines)
            self.selectedVariantID = trimmed.isEmpty ? nil : trimmed
        } else {
            self.selectedVariantID = nil
        }
        self.starredVariantIDs = try container.decodeIfPresent([String].self, forKey: .starredVariantIDs) ?? []
        self.notesByVariant = try container.decodeIfPresent([String: String].self, forKey: .notesByVariant) ?? [:]
        self.variants = try container.decodeIfPresent([String: PreviewVariantFeedback].self, forKey: .variants) ?? [:]
        self.speedMultiplier = try container.decodeIfPresent(Double.self, forKey: .speedMultiplier) ?? 1.0
        self.appearance = try container.decodeIfPresent(String.self, forKey: .appearance) ?? "light"
        self.dataState = try container.decodeIfPresent(String.self, forKey: .dataState)
            ?? VitalStridePreviewDataState.populated.rawValue
        self.allExpanded = try container.decodeIfPresent(Bool.self, forKey: .allExpanded) ?? true
        if let isoString = try? container.decodeIfPresent(String.self, forKey: .updatedAt),
           let parsedDate = ISO8601DateFormatter().date(from: isoString) {
            self.updatedAt = parsedDate
        } else if let directDate = try? container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            self.updatedAt = directDate
        } else {
            self.updatedAt = Date()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        if let selectedVariantID, !selectedVariantID.isEmpty {
            try container.encode(selectedVariantID, forKey: .selectedVariantID)
        } else {
            try container.encodeNil(forKey: .selectedVariantID)
        }
        try container.encode(starredVariantIDs, forKey: .starredVariantIDs)
        try container.encode(notesByVariant, forKey: .notesByVariant)
        try container.encode(variants, forKey: .variants)
        try container.encode(speedMultiplier, forKey: .speedMultiplier)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(dataState, forKey: .dataState)
        try container.encode(allExpanded, forKey: .allExpanded)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public var hasActiveFeedback: Bool {
        (selectedVariantID != nil && !(selectedVariantID?.isEmpty ?? true))
            || !starredVariantIDs.isEmpty
            || !notesByVariant.isEmpty
            || variants.values.contains { $0.isSelected || $0.isStarred || !$0.notes.isEmpty }
    }
}

// MARK: - 4 Loop 8 Page Tabs

/// Which of the 4 Loop 8 redesigned pages is active in `VitalStridePreviewHost`.
public enum VitalStridePreviewPageTab: Int, CaseIterable, Identifiable, Sendable {
    case page1HolisticDashboard = 1
    case page2HeartSleepCoupling = 2
    case page3WorkoutLoadProgression = 3
    case page4StepsBodySettings = 4

    public var id: Int { rawValue }

    public var goalSlug: String {
        switch self {
        case .page1HolisticDashboard: return "vs-l1-atomic-domain-cards"
        case .page2HeartSleepCoupling: return "vs-l2-cross-domain-coupling-cards"
        case .page3WorkoutLoadProgression: return "vs-l3-readiness-periodization-cards"
        case .page4StepsBodySettings: return "vs-l4-north-star-directive-cards"
        }
    }

    public var tabTitle: String {
        switch self {
        case .page1HolisticDashboard: return "L1 · 原子基元卡 (5域10指标)"
        case .page2HeartSleepCoupling: return "L2 · 跨域耦合卡 (睡眠×负荷 / NEAT×恢复)"
        case .page3WorkoutLoadProgression: return "L3 · 准备度与周期卡 (三支柱+中周期+上限%)"
        case .page4StepsBodySettings: return "L4 · 北极星指令卡 (总分+核心结论+Top3行动)"
        }
    }

    public var boardTitle: String {
        "\(tabTitle) (\(goalSlug) · v01–v10)"
    }

    public var shortcutDigit: Character {
        switch self {
        case .page1HolisticDashboard: return "1"
        case .page2HeartSleepCoupling: return "2"
        case .page3WorkoutLoadProgression: return "3"
        case .page4StepsBodySettings: return "4"
        }
    }

    public var defaultAppearance: String {
        switch self {
        case .page1HolisticDashboard, .page4StepsBodySettings:
            return "light"
        case .page2HeartSleepCoupling, .page3WorkoutLoadProgression:
            return "dark"
        }
    }

    public var snapshotFilename: String {
        switch self {
        case .page1HolisticDashboard: return "layer1-atomic-domain-cards-10up.png"
        case .page2HeartSleepCoupling: return "layer2-cross-domain-coupling-cards-10up.png"
        case .page3WorkoutLoadProgression: return "layer3-readiness-periodization-cards-10up.png"
        case .page4StepsBodySettings: return "layer4-north-star-directive-cards-10up.png"
        }
    }

    public static var handoffRootDirectory: String {
        if let custom = ProcessInfo.processInfo.environment["VS_HANDOFF_ROOT"], !custom.isEmpty {
            return custom
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Development/handoff")
            .path
    }

    public var handoffDirectory: String {
        handoffDirectory(rootDirectory: Self.handoffRootDirectory)
    }

    public func handoffDirectory(rootDirectory: String) -> String {
        "\(rootDirectory)/\(goalSlug)"
    }

    public var descriptors: [PreviewVariantDescriptor] {
        let titles: [(String, String)]
        switch self {
        case .page1HolisticDashboard:
            titles = (1...10).map { (String(format: "L1-V%02d · Atomic domain candidate", $0), "Five domain cards with ten curated aggregate metrics and a qualitative verdict.") }
        case .page2HeartSleepCoupling:
            titles = (1...10).map { (String(format: "L2-V%02d · Cross-domain coupling candidate", $0), "Sleep × training load and Daily NEAT × body recovery relationship cards.") }
        case .page3WorkoutLoadProgression:
            titles = (1...10).map { (String(format: "L3-V%02d · Readiness periodization candidate", $0), "Readiness, three pillar subscores, mesocycle phase, and intensity cap.") }
        case .page4StepsBodySettings:
            titles = (1...10).map { (String(format: "L4-V%02d · North Star directive candidate", $0), "North Star score, executive headline, provenance, and top three actions.") }
        }
        return titles.enumerated().map { index, row in
            let code = String(format: "v%02d", index + 1)
            let badge = String(format: "L%d-V%02d", rawValue, index + 1)
            return PreviewVariantDescriptor(id: code, badgeCode: badge, title: row.0, summary: row.1)
        }
    }
}

// MARK: - Receipt Persistence Writer

/// MainActor-isolated JSON receipt writer for persisting Owner `SELECT / STAR / NOTES` choices
/// to `~/Development/handoff/<goal>/receipts/preview-selection.json` and archiving prior rounds.
@MainActor
public final class PreviewSelectionReceiptWriter {
    public let fileURL: URL
    public let fallbackFileURL: URL
    private var state: PreviewSelectionReceipt = PreviewSelectionReceipt()

    public init(fileURL: URL, fallbackRootDirectory: URL? = nil, defaultAppearance: String = "light") {
        self.fileURL = fileURL
        let moduleDirectory = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
        let root = fallbackRootDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VitalStridePreviewHost/receipts", isDirectory: true)
        self.fallbackFileURL = root
            .appendingPathComponent(moduleDirectory, isDirectory: true)
            .appendingPathComponent("preview-selection.json")
        if let existing = try? Self.readReceipt(from: fileURL) {
            self.state = existing
        } else if let existing = try? Self.readReceipt(from: fallbackFileURL) {
            self.state = existing
        } else {
            self.state = PreviewSelectionReceipt(appearance: defaultAppearance)
        }
    }

    public var currentReceipt: PreviewSelectionReceipt {
        state
    }

    @discardableResult
    public func selectVariant(_ variantID: String?, now: Date = Date()) throws -> PreviewSelectionReceipt {
        let normalized = (variantID?.isEmpty == true) ? nil : variantID
        state.selectedVariantID = normalized
        for key in state.variants.keys {
            state.variants[key]?.isSelected = (key == normalized)
            state.variants[key]?.updatedAt = now
        }
        if let normalized {
            var entry = state.variants[normalized] ?? PreviewVariantFeedback(variantID: normalized, updatedAt: now)
            entry.isSelected = true
            entry.updatedAt = now
            state.variants[normalized] = entry
        }
        state.updatedAt = now
        try persistReceipt(state)
        return state
    }

    @discardableResult
    public func toggleStar(for variantID: String, now: Date = Date()) throws -> PreviewSelectionReceipt {
        var entry = state.variants[variantID] ?? PreviewVariantFeedback(variantID: variantID, updatedAt: now)
        if state.starredVariantIDs.contains(variantID) {
            entry.isStarred = false
        } else {
            entry.isStarred = true
        }
        entry.updatedAt = now
        state.variants[variantID] = entry
        var set = Set(state.starredVariantIDs)
        if entry.isStarred {
            set.insert(variantID)
        } else {
            set.remove(variantID)
        }
        state.starredVariantIDs = set.sorted()
        state.updatedAt = now
        try persistReceipt(state)
        return state
    }

    @discardableResult
    public func updateNotes(for variantID: String, notes: String, now: Date = Date()) throws -> PreviewSelectionReceipt {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = state.variants[variantID] ?? PreviewVariantFeedback(variantID: variantID, updatedAt: now)
        entry.notes = trimmed
        entry.updatedAt = now
        state.variants[variantID] = entry
        if trimmed.isEmpty {
            state.notesByVariant.removeValue(forKey: variantID)
        } else {
            state.notesByVariant[variantID] = trimmed
        }
        state.updatedAt = now
        try persistReceipt(state)
        return state
    }

    @discardableResult
    public func updateHostEnvironment(
        speedMultiplier: PreviewSpeedMultiplier,
        appearance: String,
        dataState: VitalStridePreviewDataState,
        allExpanded: Bool,
        now: Date = Date()
    ) throws -> PreviewSelectionReceipt {
        state.speedMultiplier = speedMultiplier.rawValue
        state.appearance = appearance
        state.dataState = dataState.rawValue
        state.allExpanded = allExpanded
        state.updatedAt = now
        try persistReceipt(state)
        return state
    }

    @discardableResult
    public func archiveAndResetRound(
        explicitRound: Int? = nil,
        defaultAppearance: String? = nil,
        now: Date = Date()
    ) throws -> (archivedURL: URL?, resetReceipt: PreviewSelectionReceipt) {
        let primaryDirectory = fileURL.deletingLastPathComponent()
        let directory: URL
        do {
            try FileManager.default.createDirectory(at: primaryDirectory, withIntermediateDirectories: true)
            directory = primaryDirectory
        } catch {
            directory = fallbackFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let existingFiles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let existingRounds = existingFiles.compactMap { url -> Int? in
            let name = url.lastPathComponent
            if let match = name.range(of: #"^preview-selection\.round-(\d+)\.json$"#, options: .regularExpression) {
                return Int(name[match].dropFirst("preview-selection.round-".count).dropLast(".json".count))
            }
            if let match = name.range(of: #"^preview-selection-r(\d+)\.json$"#, options: .regularExpression) {
                return Int(name[match].dropFirst("preview-selection-r".count).dropLast(".json".count))
            }
            return nil
        }

        let round = max(explicitRound ?? ((existingRounds.max() ?? 0) + 1), 1)
        var archivedURL: URL?
        if FileManager.default.fileExists(atPath: fileURL.path) || state.hasActiveFeedback {
            let roundTarget = directory.appendingPathComponent("preview-selection.round-\(round).json")
            let shortTarget = directory.appendingPathComponent("preview-selection-r\(round).json")
            try Self.writeReceipt(state, to: roundTarget)
            try? Self.writeReceipt(state, to: shortTarget)
            archivedURL = roundTarget
        }

        let reset = PreviewSelectionReceipt(
            schema: PreviewSelectionReceipt.currentSchemaVersion,
            selectedVariantID: nil,
            starredVariantIDs: [],
            notesByVariant: [:],
            variants: [:],
            speedMultiplier: state.speedMultiplier,
            appearance: defaultAppearance ?? state.appearance,
            dataState: VitalStridePreviewDataState.populated.rawValue,
            allExpanded: true,
            updatedAt: now
        )
        state = reset
        try persistReceipt(reset)
        return (archivedURL, reset)
    }

    private func persistReceipt(_ receipt: PreviewSelectionReceipt) throws {
        do {
            try Self.writeReceipt(receipt, to: fileURL)
            try? Self.writeReceipt(receipt, to: fallbackFileURL)
        } catch {
            try Self.writeReceipt(receipt, to: fallbackFileURL)
        }
    }

    private static func readReceipt(from url: URL) throws -> PreviewSelectionReceipt {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PreviewSelectionReceipt.self, from: data)
    }

    private static func writeReceipt(_ receipt: PreviewSelectionReceipt, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Snapshot Environment Key

private struct VitalStridePreviewSnapshotModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var vsPreviewSnapshotMode: Bool {
        get { self[VitalStridePreviewSnapshotModeKey.self] }
        set { self[VitalStridePreviewSnapshotModeKey.self] = newValue }
    }
}

// MARK: - Per-Page 10-Up Controller & Coordinator

@MainActor
public final class VitalStridePagePreviewController: ObservableObject {
    public let page: VitalStridePreviewPageTab
    public let variants: [PreviewVariantDescriptor]
    public let receiptWriter: PreviewSelectionReceiptWriter

    @Published public var speedMultiplier: PreviewSpeedMultiplier = .x1_0 {
        didSet { persistEnvironmentIfNeeded() }
    }
    @Published public var colorScheme: ColorScheme = .light {
        didSet { persistEnvironmentIfNeeded() }
    }
    @Published public var dataState: VitalStridePreviewDataState = .populated {
        didSet { persistEnvironmentIfNeeded() }
    }
    @Published public var allExpanded: Bool = true {
        didSet { persistEnvironmentIfNeeded() }
    }
    @Published public private(set) var expandedByVariant: [String: Bool]
    @Published public private(set) var selectedVariantID: String?
    @Published public private(set) var starredVariantIDs: Set<String> = []
    @Published public private(set) var notesByVariant: [String: String] = [:]
    @Published public private(set) var roundEpoch: UInt64 = 0
    @Published public var zoomedDescriptor: PreviewVariantDescriptor?

    private var pendingDraftNotes: [String: String] = [:]
    private var isHydrating = false

    public init(
        page: VitalStridePreviewPageTab,
        handoffRootDirectory: String? = nil
    ) {
        self.page = page
        self.variants = page.descriptors
        let rootDir = handoffRootDirectory ?? VitalStridePreviewPageTab.handoffRootDirectory
        let receiptURL = URL(
            fileURLWithPath: "\(page.handoffDirectory(rootDirectory: rootDir))/receipts/preview-selection.json"
        )
        let fileExists = FileManager.default.fileExists(atPath: receiptURL.path)
        let writer = PreviewSelectionReceiptWriter(
            fileURL: receiptURL,
            defaultAppearance: page.defaultAppearance
        )
        self.receiptWriter = writer

        var initialExpanded: [String: Bool] = [:]
        for variant in page.descriptors {
            initialExpanded[variant.id] = true
        }
        self.expandedByVariant = initialExpanded

        isHydrating = true
        let existing = writer.currentReceipt
        self.selectedVariantID = existing.selectedVariantID
        self.starredVariantIDs = Set(existing.starredVariantIDs)
        self.notesByVariant = existing.notesByVariant
        let appearance = fileExists ? existing.appearance : page.defaultAppearance
        self.colorScheme = (appearance == "dark") ? .dark : .light
        if fileExists, let speed = PreviewSpeedMultiplier(rawValue: existing.speedMultiplier) {
            self.speedMultiplier = speed
        }
        if fileExists, let restoredState = VitalStridePreviewDataState(rawValue: existing.dataState) {
            self.dataState = restoredState
        }
        let expandedFlag = fileExists ? existing.allExpanded : true
        self.allExpanded = expandedFlag
        var map: [String: Bool] = [:]
        for variant in page.descriptors {
            map[variant.id] = expandedFlag
        }
        self.expandedByVariant = map
        isHydrating = false
    }

    public var appearanceName: String {
        colorScheme == .dark ? "dark" : "light"
    }

    public func isExpanded(for variantID: String) -> Bool {
        expandedByVariant[variantID] ?? allExpanded
    }

    public func toggleExpanded(for variantID: String, animated: Bool = true) {
        let next = !(expandedByVariant[variantID] ?? allExpanded)
        let descriptor = variants.first { $0.id == variantID }
        let anim = descriptor?.spring(for: speedMultiplier) ?? speedMultiplier.scaledSpring()
        if animated {
            withAnimation(anim) {
                expandedByVariant[variantID] = next
            }
        } else {
            expandedByVariant[variantID] = next
        }
    }

    public func reloadErrorState() {
        dataState = .populated
    }

    public func toggleAllExpanded(animated: Bool = true) {
        let next = !allExpanded
        let anim = speedMultiplier.scaledSpring()
        let apply = {
            self.allExpanded = next
            for variant in self.variants {
                self.expandedByVariant[variant.id] = next
            }
        }
        if animated {
            withAnimation(anim, apply)
        } else {
            apply()
        }
    }

    public func selectVariant(_ variantID: String?) {
        selectedVariantID = variantID
        _ = try? receiptWriter.selectVariant(variantID)
    }

    public func toggleStar(for variantID: String) {
        if starredVariantIDs.contains(variantID) {
            starredVariantIDs.remove(variantID)
        } else {
            starredVariantIDs.insert(variantID)
        }
        _ = try? receiptWriter.toggleStar(for: variantID)
    }

    public func stageDraftNote(for variantID: String, draft: String, roundEpoch expectedEpoch: UInt64? = nil) {
        if let expectedEpoch, expectedEpoch != roundEpoch {
            return
        }
        pendingDraftNotes[variantID] = draft
    }

    public func settlePendingDraftNotes() {
        guard !pendingDraftNotes.isEmpty else { return }
        let staged = pendingDraftNotes
        pendingDraftNotes.removeAll()
        for (variantID, rawDraft) in staged {
            let trimmed = rawDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let persisted = notesByVariant[variantID] ?? ""
            if trimmed != persisted {
                updateNotes(for: variantID, notes: trimmed)
            }
        }
    }

    public func updateNotes(for variantID: String, notes: String, roundEpoch expectedEpoch: UInt64? = nil) {
        if let expectedEpoch, expectedEpoch != roundEpoch {
            return
        }
        pendingDraftNotes.removeValue(forKey: variantID)
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notesByVariant.removeValue(forKey: variantID)
        } else {
            notesByVariant[variantID] = trimmed
        }
        _ = try? receiptWriter.updateNotes(for: variantID, notes: trimmed)
    }

    @discardableResult
    public func archiveAndResetRound(explicitRound: Int? = nil) throws -> URL? {
        settlePendingDraftNotes()
        let result = try receiptWriter.archiveAndResetRound(
            explicitRound: explicitRound,
            defaultAppearance: appearanceName
        )
        pendingDraftNotes.removeAll()
        roundEpoch &+= 1
        selectedVariantID = result.resetReceipt.selectedVariantID
        starredVariantIDs = Set(result.resetReceipt.starredVariantIDs)
        notesByVariant = result.resetReceipt.notesByVariant
        allExpanded = result.resetReceipt.allExpanded
        expandedByVariant = Dictionary(uniqueKeysWithValues: variants.map { ($0.id, true) })
        return result.archivedURL
    }

    private func persistEnvironmentIfNeeded() {
        guard !isHydrating else { return }
        _ = try? receiptWriter.updateHostEnvironment(
            speedMultiplier: speedMultiplier,
            appearance: appearanceName,
            dataState: dataState,
            allExpanded: allExpanded
        )
    }
}

/// Top-level coordinator managing all 4 Loop 8 page controllers and global controls.
@MainActor
public final class VitalStridePreviewBoardCoordinator: ObservableObject {
    @Published public var activePage: VitalStridePreviewPageTab
    @Published public var statusBannerMessage: String?

    public let page1Controller: VitalStridePagePreviewController
    public let page2Controller: VitalStridePagePreviewController
    public let page3Controller: VitalStridePagePreviewController
    public let page4Controller: VitalStridePagePreviewController

    public init(
        initialPage: VitalStridePreviewPageTab = .page1HolisticDashboard,
        handoffRootDirectory: String? = nil
    ) {
        self.activePage = initialPage
        self.page1Controller = VitalStridePagePreviewController(
            page: .page1HolisticDashboard,
            handoffRootDirectory: handoffRootDirectory
        )
        self.page2Controller = VitalStridePagePreviewController(
            page: .page2HeartSleepCoupling,
            handoffRootDirectory: handoffRootDirectory
        )
        self.page3Controller = VitalStridePagePreviewController(
            page: .page3WorkoutLoadProgression,
            handoffRootDirectory: handoffRootDirectory
        )
        self.page4Controller = VitalStridePagePreviewController(
            page: .page4StepsBodySettings,
            handoffRootDirectory: handoffRootDirectory
        )
    }

    public var allControllers: [VitalStridePagePreviewController] {
        [page1Controller, page2Controller, page3Controller, page4Controller]
    }

    public func controller(for page: VitalStridePreviewPageTab) -> VitalStridePagePreviewController {
        switch page {
        case .page1HolisticDashboard: return page1Controller
        case .page2HeartSleepCoupling: return page2Controller
        case .page3WorkoutLoadProgression: return page3Controller
        case .page4StepsBodySettings: return page4Controller
        }
    }

    public var currentController: VitalStridePagePreviewController {
        controller(for: activePage)
    }

    public func switchPage(to nextPage: VitalStridePreviewPageTab, animated: Bool = true) {
        guard nextPage != activePage else { return }
        currentController.settlePendingDraftNotes()
        if animated {
            withAnimation(.snappy(duration: 0.22)) {
                activePage = nextPage
            }
        } else {
            activePage = nextPage
        }
    }

    public func archiveAndResetAllPages(explicitRound: Int? = nil) {
        var archivedCount = 0
        for ctrl in allControllers {
            if let _ = try? ctrl.archiveAndResetRound(explicitRound: explicitRound) {
                archivedCount += 1
            }
        }
        statusBannerMessage = "已归档上一轮并清空 4 大页面选型与批注（Archived \(archivedCount) page receipts）"
    }
}

// MARK: - Viewport Context & Equatable Isolation Host

public struct PreviewViewportContext: Sendable, Equatable {
    public let page: VitalStridePreviewPageTab
    public let descriptor: PreviewVariantDescriptor
    public let dataState: VitalStridePreviewDataState
    public let isExpanded: Bool
    public let speedMultiplier: PreviewSpeedMultiplier
    public let colorScheme: ColorScheme

    public init(
        page: VitalStridePreviewPageTab,
        descriptor: PreviewVariantDescriptor,
        dataState: VitalStridePreviewDataState,
        isExpanded: Bool,
        speedMultiplier: PreviewSpeedMultiplier,
        colorScheme: ColorScheme
    ) {
        self.page = page
        self.descriptor = descriptor
        self.dataState = dataState
        self.isExpanded = isExpanded
        self.speedMultiplier = speedMultiplier
        self.colorScheme = colorScheme
    }
}

@MainActor
public struct IsolatedCandidateViewportHost: View, Equatable {
    public let context: PreviewViewportContext

    public init(context: PreviewViewportContext) {
        self.context = context
    }

    public nonisolated static func == (
        lhs: IsolatedCandidateViewportHost,
        rhs: IsolatedCandidateViewportHost
    ) -> Bool {
        lhs.context == rhs.context
    }

    public var body: some View {
        let isDark = context.colorScheme == .dark
        let resolvedTheme = Theme(seed: .teal, neutral: .slate, isDark: isDark)
        candidateBody
            .environment(\.theme, resolvedTheme)
            .environment(\.colorScheme, context.colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(resolvedTheme.canvas)
            .foregroundStyle(resolvedTheme.foreground)
    }

    @ViewBuilder
    private var candidateBody: some View {
        let variantNumber = Int(context.descriptor.id.dropFirst()) ?? 1
        let layer = LayeredComponentLayer(rawValue: context.page.rawValue) ?? .l1
        LayeredComponentCandidateView(
            data: LayeredComponentGalleryPreviewData(
                layer: layer,
                variant: variantNumber,
                state: context.dataState
            )
        )
    }
}

// MARK: - Per-Card SELECT / STAR / NOTES Action Bar

@MainActor
public struct PreviewVariantSelectionBar: View {
    public let variantID: String
    public let roundEpoch: UInt64
    public let isSelected: Bool
    public let isStarred: Bool
    public let persistedNote: String
    public let theme: Theme
    public let snapshotMode: Bool
    public let onToggleSelect: () -> Void
    public let onToggleStar: () -> Void
    public let onStageDraft: (String, UInt64) -> Void
    public let onCommitNotes: (String, UInt64) -> Void

    @State private var draftNote: String

    public init(
        variantID: String,
        roundEpoch: UInt64 = 0,
        isSelected: Bool,
        isStarred: Bool,
        persistedNote: String,
        theme: Theme,
        snapshotMode: Bool,
        onToggleSelect: @escaping () -> Void,
        onToggleStar: @escaping () -> Void,
        onStageDraft: @escaping (String, UInt64) -> Void = { _, _ in },
        onCommitNotes: @escaping (String, UInt64) -> Void
    ) {
        self.variantID = variantID
        self.roundEpoch = roundEpoch
        self.isSelected = isSelected
        self.isStarred = isStarred
        self.persistedNote = persistedNote
        self.theme = theme
        self.snapshotMode = snapshotMode
        self.onToggleSelect = onToggleSelect
        self.onToggleStar = onToggleStar
        self.onStageDraft = onStageDraft
        self.onCommitNotes = onCommitNotes
        self._draftNote = State(initialValue: persistedNote)
    }

    public var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleSelect) {
                HStack(spacing: 4) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    Text("SELECT")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? theme.onInteractiveAccent : theme.foreground)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(isSelected ? theme.interactiveAccent : theme.inner, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onToggleStar) {
                HStack(spacing: 4) {
                    Image(systemName: isStarred ? "star.fill" : "star")
                    Text("STAR")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(isStarred ? theme.warning : theme.foreground)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(theme.inner, in: Capsule())
            }
            .buttonStyle(.plain)

            if snapshotMode {
                Text(persistedNote.isEmpty ? "批注反馈 (NOTES)…" : persistedNote)
                    .font(.caption2)
                    .foregroundStyle(persistedNote.isEmpty ? theme.secondaryForeground : theme.foreground)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(theme.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                let capturedEpoch = roundEpoch
                TextField("批注反馈 (NOTES)…", text: $draftNote)
                    .font(.caption2)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .background(theme.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: draftNote) { _, newValue in
                        onStageDraft(newValue, capturedEpoch)
                    }
                    .onSubmit {
                        commitDraftIfNeeded(epoch: capturedEpoch)
                    }
                    .onDisappear {
                        commitDraftIfNeeded(epoch: capturedEpoch)
                    }
                    .task(id: "\(roundEpoch)::\(draftNote)") {
                        guard draftNote.trimmingCharacters(in: .whitespacesAndNewlines) != persistedNote else { return }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        commitDraftIfNeeded(epoch: capturedEpoch)
                    }
                    .onChange(of: roundEpoch) { _, _ in
                        draftNote = persistedNote
                    }
                    .onChange(of: persistedNote) { _, newValue in
                        if draftNote.trimmingCharacters(in: .whitespacesAndNewlines) != newValue {
                            draftNote = newValue
                        }
                    }
                    .onChange(of: variantID) { _, _ in
                        draftNote = persistedNote
                    }
            }
        }
        .frame(width: 393)
    }

    private func commitDraftIfNeeded(epoch: UInt64) {
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != persistedNote else { return }
        onCommitNotes(trimmed, epoch)
    }
}

// MARK: - Complete 4-Page × 10-Up Native SwiftUI Preview Host Board

@MainActor
public struct VitalStridePreviewHostBoard: View {
    @StateObject private var stateCoordinator: VitalStridePreviewBoardCoordinator
    private let externalCoordinator: VitalStridePreviewBoardCoordinator?

    public var coordinator: VitalStridePreviewBoardCoordinator {
        externalCoordinator ?? stateCoordinator
    }

    public init(
        initialPage: VitalStridePreviewPageTab = .page1HolisticDashboard,
        handoffRootDirectory: String? = nil
    ) {
        let created = VitalStridePreviewBoardCoordinator(
            initialPage: initialPage,
            handoffRootDirectory: handoffRootDirectory
        )
        self._stateCoordinator = StateObject(wrappedValue: created)
        self.externalCoordinator = nil
    }

    public init(coordinator: VitalStridePreviewBoardCoordinator) {
        self._stateCoordinator = StateObject(wrappedValue: coordinator)
        self.externalCoordinator = coordinator
    }

    public var body: some View {
        VitalStridePreviewHostBoardContent(coordinator: coordinator)
    }
}

@MainActor
private struct VitalStridePreviewHostBoardContent: View {
    @ObservedObject var coordinator: VitalStridePreviewBoardCoordinator
    @Environment(\.vsPreviewSnapshotMode) private var snapshotMode
    @Environment(\.colorScheme) private var envColorScheme

    private var currentController: VitalStridePagePreviewController {
        coordinator.currentController
    }

    private var effectiveColorScheme: ColorScheme {
        snapshotMode ? envColorScheme : currentController.colorScheme
    }

    private var resolvedTheme: Theme {
        Theme(seed: .teal, neutral: .slate, isDark: effectiveColorScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 0) {
            pageTabBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(resolvedTheme.surface)

            Divider()

            VitalStrideSinglePageGalleryView(
                coordinator: coordinator,
                controller: currentController,
                theme: resolvedTheme
            )
        }
        .environment(\.theme, resolvedTheme)
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(effectiveColorScheme)
    }

    private var pageTabBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .foregroundStyle(resolvedTheme.accent)
                Text("VitalStride 4-Layer 10-Up Component Gallery")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(resolvedTheme.foreground)
            }

            ForEach(VitalStridePreviewPageTab.allCases) { tab in
                let isSelected = coordinator.activePage == tab
                let tabController = coordinator.controller(for: tab)
                Button {
                    guard !snapshotMode else { return }
                    coordinator.switchPage(to: tab, animated: true)
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.tabTitle)
                            .font(.caption.weight(.bold))
                        if let sel = tabController.selectedVariantID, !sel.isEmpty {
                            Text("✓\(sel.uppercased())")
                                .font(.caption2.weight(.black).monospaced())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    isSelected ? resolvedTheme.onInteractiveAccent.opacity(0.22) : resolvedTheme.accentSubtle,
                                    in: Capsule()
                                )
                        }
                        if !tabController.starredVariantIDs.isEmpty {
                            Text("★\(tabController.starredVariantIDs.count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(isSelected ? resolvedTheme.onInteractiveAccent : resolvedTheme.warning)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        isSelected ? resolvedTheme.interactiveAccent : resolvedTheme.inner,
                        in: Capsule()
                    )
                    .foregroundStyle(isSelected ? resolvedTheme.onInteractiveAccent : resolvedTheme.foreground)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(tab.shortcutDigit), modifiers: .command)
            }

            Spacer()

            if let banner = coordinator.statusBannerMessage {
                Text(banner)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(resolvedTheme.success)
                    .lineLimit(1)
            }
        }
    }
}

@MainActor
private struct VitalStrideSinglePageGalleryView: View {
    @ObservedObject var coordinator: VitalStridePreviewBoardCoordinator
    @ObservedObject var controller: VitalStridePagePreviewController
    let theme: Theme
    @Environment(\.vsPreviewSnapshotMode) private var snapshotMode

    private var interactiveVariantRows: [[PreviewVariantDescriptor]] {
        let columnCount = 3
        return stride(from: 0, to: controller.variants.count, by: columnCount).map { startIndex in
            Array(controller.variants[startIndex..<min(startIndex + columnCount, controller.variants.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topControlToolbar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(theme.surfaceSubtle)

            Divider()

            if snapshotMode {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(393), spacing: 18), count: 5), spacing: 18) {
                    ForEach(controller.variants) { descriptor in
                        variantColumn(for: descriptor)
                    }
                }
                .padding(22)
                .frame(width: 2140, height: 1320, alignment: .topLeading)
                .background(theme.canvas)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(interactiveVariantRows.enumerated()), id: \.offset) { _, rowVariants in
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(rowVariants) { descriptor in
                                    variantColumn(for: descriptor)
                                }
                            }
                        }
                    }
                    .padding(22)
                }
                .background(theme.canvas)
            }
        }
        .sheet(item: $controller.zoomedDescriptor) { descriptor in
            CandidateFullSheetModal(
                page: controller.page,
                descriptor: descriptor,
                controller: controller,
                theme: theme
            )
        }
    }

    private var topControlToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.page.boardTitle)
                    .font(.headline.bold())
                    .foregroundStyle(theme.foreground)
                Text("100% Native SwiftUI · 4 Layers × v01–v10 · 120Hz Interactive Host · Live SELECT/STAR/NOTES Receipt Sync")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryForeground)
                Text(controller.receiptWriter.fileURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.tertiaryForeground)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("状态")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryForeground)
                    .padding(.leading, 6)
                ForEach(VitalStridePreviewDataState.allCases) { stateItem in
                    let selected = controller.dataState == stateItem
                    Button {
                        guard !snapshotMode else { return }
                        controller.dataState = stateItem
                    } label: {
                        Text(stateItem.label)
                            .font(.caption.weight(selected ? .bold : .medium))
                            .foregroundStyle(selected ? theme.onInteractiveAccent : theme.foreground)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(selected ? theme.interactiveAccent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if controller.dataState == .error {
                    Button {
                        guard !snapshotMode else { return }
                        controller.reloadErrorState()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.onInteractiveAccent)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(theme.warning, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(theme.inner, in: Capsule())

            HStack(spacing: 4) {
                Text("倍率")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryForeground)
                    .padding(.leading, 6)
                ForEach(PreviewSpeedMultiplier.allCases) { speed in
                    let selected = controller.speedMultiplier == speed
                    Button {
                        guard !snapshotMode else { return }
                        controller.speedMultiplier = speed
                    } label: {
                        Text(speed.label)
                            .font(.caption.weight(selected ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(selected ? theme.onInteractiveAccent : theme.foreground)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(selected ? theme.interactiveAccent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(theme.inner, in: Capsule())

            HStack(spacing: 4) {
                appearanceButton(label: "Light", scheme: .light, icon: "sun.max.fill")
                appearanceButton(label: "Dark", scheme: .dark, icon: "moon.fill")
            }
            .padding(4)
            .background(theme.inner, in: Capsule())

            Button {
                guard !snapshotMode else { return }
                controller.toggleAllExpanded(animated: true)
            } label: {
                Label(
                    controller.allExpanded ? "紧凑视图" : "展开全高",
                    systemImage: controller.allExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.onInteractiveAccent)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(theme.interactiveAccent, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                guard !snapshotMode else { return }
                coordinator.archiveAndResetAllPages()
            } label: {
                Label("新一轮清空 (Archive & Reset)", systemImage: "archivebox.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(theme.danger, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新一轮清空选型与批注")
        }
    }

    private func appearanceButton(label: String, scheme: ColorScheme, icon: String) -> some View {
        let selected = controller.colorScheme == scheme
        return Button {
            guard !snapshotMode else { return }
            controller.colorScheme = scheme
        } label: {
            Label(label, systemImage: icon)
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? theme.onInteractiveAccent : theme.foreground)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(selected ? theme.interactiveAccent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func variantColumn(for descriptor: PreviewVariantDescriptor) -> some View {
        let expanded = controller.isExpanded(for: descriptor.id)
        let isSelected = controller.selectedVariantID == descriptor.id
        let isStarred = controller.starredVariantIDs.contains(descriptor.id)
        let persistedNote = controller.notesByVariant[descriptor.id] ?? ""
        let context = PreviewViewportContext(
            page: controller.page,
            descriptor: descriptor,
            dataState: controller.dataState,
            isExpanded: expanded,
            speedMultiplier: controller.speedMultiplier,
            colorScheme: controller.colorScheme
        )
        let cardHeight: CGFloat = snapshotMode ? 480 : (expanded ? 760 : 440)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(descriptor.badgeCode)
                    .font(.caption.weight(.black).monospaced())
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.accentSubtle, in: Capsule())

                Text(descriptor.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)

                Spacer()

                if !snapshotMode {
                    Button {
                        controller.toggleExpanded(for: descriptor.id, animated: true)
                    } label: {
                        Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.secondaryForeground)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(theme.inner, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "切换为紧凑高度 (440pt)" : "切换为完整高度 (760pt)")

                    Button {
                        controller.zoomedDescriptor = descriptor
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(theme.inner, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("全屏检视该候选视图")
                }
            }

            Text(descriptor.summary)
                .font(.caption)
                .foregroundStyle(theme.secondaryForeground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 393, alignment: .leading)

            PreviewVariantSelectionBar(
                variantID: descriptor.id,
                roundEpoch: controller.roundEpoch,
                isSelected: isSelected,
                isStarred: isStarred,
                persistedNote: persistedNote,
                theme: theme,
                snapshotMode: snapshotMode,
                onToggleSelect: {
                    guard !snapshotMode else { return }
                    controller.selectVariant(isSelected ? nil : descriptor.id)
                },
                onToggleStar: {
                    guard !snapshotMode else { return }
                    controller.toggleStar(for: descriptor.id)
                },
                onStageDraft: { draft, epoch in
                    guard !snapshotMode else { return }
                    controller.stageDraftNote(for: descriptor.id, draft: draft, roundEpoch: epoch)
                },
                onCommitNotes: { notes, epoch in
                    guard !snapshotMode else { return }
                    controller.updateNotes(for: descriptor.id, notes: notes, roundEpoch: epoch)
                }
            )
            .id("\(controller.page.goalSlug)::\(descriptor.id)::\(controller.roundEpoch)")

            IsolatedCandidateViewportHost(context: context)
                .equatable()
                .frame(width: 393, height: cardHeight, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            isSelected ? theme.accent : theme.border,
                            lineWidth: isSelected ? 2.5 : 1.2
                        )
                }
        }
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2.0 : 1.0)
        }
    }
}

// MARK: - Full-Sheet Zoom Modal

@MainActor
private struct CandidateFullSheetModal: View {
    let page: VitalStridePreviewPageTab
    let descriptor: PreviewVariantDescriptor
    @ObservedObject var controller: VitalStridePagePreviewController
    let theme: Theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let isSelected = controller.selectedVariantID == descriptor.id
        let isStarred = controller.starredVariantIDs.contains(descriptor.id)
        let persistedNote = controller.notesByVariant[descriptor.id] ?? ""
        let context = PreviewViewportContext(
            page: page,
            descriptor: descriptor,
            dataState: controller.dataState,
            isExpanded: true,
            speedMultiplier: controller.speedMultiplier,
            colorScheme: controller.colorScheme
        )

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(descriptor.badgeCode)
                    .font(.caption.weight(.black).monospaced())
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accentSubtle, in: Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(page.tabTitle) · \(descriptor.title)")
                        .font(.headline.bold())
                        .foregroundStyle(theme.foreground)
                    Text(descriptor.summary)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryForeground)
                }

                Spacer()

                PreviewVariantSelectionBar(
                    variantID: descriptor.id,
                    roundEpoch: controller.roundEpoch,
                    isSelected: isSelected,
                    isStarred: isStarred,
                    persistedNote: persistedNote,
                    theme: theme,
                    snapshotMode: false,
                    onToggleSelect: {
                        controller.selectVariant(isSelected ? nil : descriptor.id)
                    },
                    onToggleStar: {
                        controller.toggleStar(for: descriptor.id)
                    },
                    onStageDraft: { draft, epoch in
                        controller.stageDraftNote(for: descriptor.id, draft: draft, roundEpoch: epoch)
                    },
                    onCommitNotes: { notes, epoch in
                        controller.updateNotes(for: descriptor.id, notes: notes, roundEpoch: epoch)
                    }
                )

                Button {
                    dismiss()
                } label: {
                    Label("关闭", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.foreground)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(theme.inner, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(theme.surface)

            Divider()

            ScrollView {
                HStack {
                    Spacer()
                    IsolatedCandidateViewportHost(context: context)
                        .frame(width: 430, height: 880, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1.5)
                        }
                        .padding(24)
                    Spacer()
                }
            }
            .background(theme.canvas)
        }
        .frame(minWidth: 980, minHeight: 920)
        .environment(\.theme, theme)
        .environment(\.colorScheme, controller.colorScheme)
    }
}

#Preview("VitalStride 4-Page 10-Up Preview Host · Light") {
    VitalStridePreviewHostBoard(initialPage: .page1HolisticDashboard)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

#Preview("VitalStride 4-Page 10-Up Preview Host · Dark") {
    VitalStridePreviewHostBoard(initialPage: .page2HeartSleepCoupling)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.dark)
}
