import DesignKit
import HealthKitService
import SwiftUI

// MARK: - Injectable seam

/// Injectable seam for pushing a `WatchScreenConfig` to the paired watch.
///
/// The production wiring (see `SettingsView`) captures the environment
/// `HealthKitService`, creates a `WorkoutSessionManaging` via
/// `makeWorkoutSessionManager()`, and forwards to
/// `updateWatchScreenConfig(_:)`. Tests inject a recording closure so we
/// can assert what the settings UI pushes without spinning up a
/// `WCSession` or HealthKit.
public typealias WatchScreenConfigPusher = @Sendable (WatchScreenConfig) async -> Void

// MARK: - Model

/// UserDefaults-backed model for the iOS Settings → 训练 → 手表训练屏 screen.
///
/// Responsibilities:
///   1. Load persisted preset + module toggles (`WatchScreenConfig.Preset`
///      + `Set<WatchScreenConfig.Module>`). Missing or malformed storage
///      falls back to the deterministic default (`fullInfo`, all modules
///      on) per `specs/watch-in-workout-screen.md` §7 "Watch fallback".
///   2. Enforce the locked-on invariants (`heartRate`, `primaryAction`)
///      end-to-end: UI cannot disable them, persistence layer cannot
///      store a config that omits them, and pushes always contain them
///      (also enforced by `WatchScreenConfig.init` on the receiving end).
///   3. Push the full config through the injected `pusher` seam on every
///      user-driven change so the paired watch stays in sync.
///
/// Not persisted here: any HK health values. `WatchScreenConfig` carries
/// only app configuration.
@MainActor
final class WatchScreenSettingsModel: ObservableObject {
    /// UserDefaults key for the persisted preset raw value.
    static let presetStorageKey = "watchScreen.preset"
    /// UserDefaults key for the persisted module set, comma-separated
    /// module raw values in `Module.allCases` order.
    static let modulesStorageKey = "watchScreen.enabledModules"

    @Published private(set) var preset: WatchScreenConfig.Preset
    @Published private(set) var enabledModules: Set<WatchScreenConfig.Module>

    private let now: @Sendable () -> Date
    private let pusher: WatchScreenConfigPusher
    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        pusher: @escaping WatchScreenConfigPusher
    ) {
        self.userDefaults = userDefaults
        self.now = now
        self.pusher = pusher

        let decoded = Self.load(from: userDefaults)
        self.preset = decoded.preset
        self.enabledModules = decoded.enabledModules
    }

    // MARK: Mutations

    /// Update the layer preset. Persists synchronously and schedules a
    /// push of the resulting full config through the injected seam.
    @discardableResult
    func setPreset(_ preset: WatchScreenConfig.Preset) -> Task<Void, Never> {
        self.preset = preset
        userDefaults.set(preset.rawValue, forKey: Self.presetStorageKey)
        return schedulePush()
    }

    /// Enable or disable a module toggle. Attempts to disable a locked-on
    /// module (`heartRate` / `primaryAction`) are silently ignored — the
    /// UI already disables those rows; this second gate exists for tests
    /// and for future callers that construct the model directly.
    @discardableResult
    func setModule(
        _ module: WatchScreenConfig.Module,
        enabled: Bool
    ) -> Task<Void, Never> {
        if !enabled, WatchScreenConfig.lockedOnModules.contains(module) {
            // No mutation, no push. State is already consistent.
            return Task { }
        }
        var next = enabledModules
        if enabled {
            next.insert(module)
        } else {
            next.remove(module)
        }
        // Explicitly keep locked-on modules in storage so a future decoder
        // sees the invariant even without needing to re-apply it.
        let effective = next.union(WatchScreenConfig.lockedOnModules)
        enabledModules = effective
        userDefaults.set(
            Self.encodeModules(effective),
            forKey: Self.modulesStorageKey
        )
        return schedulePush()
    }

    /// Snapshot of the current UI state as a canonical `WatchScreenConfig`.
    /// The `WatchScreenConfig.init` re-applies the locked-on invariant.
    var currentConfig: WatchScreenConfig {
        WatchScreenConfig(preset: preset, enabledModules: enabledModules, updatedAt: now())
    }

    private func schedulePush() -> Task<Void, Never> {
        let config = currentConfig
        let pusher = self.pusher
        return Task { await pusher(config) }
    }

    // MARK: Persistence encoding/decoding (pure)

    struct StoredState: Equatable {
        var preset: WatchScreenConfig.Preset
        var enabledModules: Set<WatchScreenConfig.Module>
    }

    /// Load stored preset + modules from `defaults`. Missing entries fall
    /// back to the default state (`fullInfo`, all modules on).
    static func load(from defaults: UserDefaults) -> StoredState {
        let preset = decodePreset(defaults.string(forKey: presetStorageKey))
        let modules = decodeModules(defaults.string(forKey: modulesStorageKey))
        return StoredState(preset: preset, enabledModules: modules)
    }

    /// Decode a preset raw value. Unknown / nil → `.fullInfo` default.
    static func decodePreset(_ raw: String?) -> WatchScreenConfig.Preset {
        guard let raw, let preset = WatchScreenConfig.Preset(rawValue: raw) else {
            return .fullInfo
        }
        return preset
    }

    /// Decode a comma-separated module raw-value list. Missing storage,
    /// empty string, or entirely-unknown tokens all fall back to
    /// `Module.allCases`. Locked-on modules are always folded in.
    static func decodeModules(_ raw: String?) -> Set<WatchScreenConfig.Module> {
        guard let raw else {
            return Set(WatchScreenConfig.Module.allCases)
        }
        let tokens = raw.split(separator: ",").map(String.init)
        let known: [WatchScreenConfig.Module] = tokens.compactMap {
            WatchScreenConfig.Module(rawValue: $0)
        }
        if tokens.isEmpty || known.isEmpty {
            return Set(WatchScreenConfig.Module.allCases)
        }
        return Set(known).union(WatchScreenConfig.lockedOnModules)
    }

    /// Deterministic serialization: modules in `Module.allCases` order.
    static func encodeModules(_ modules: Set<WatchScreenConfig.Module>) -> String {
        WatchScreenConfig.Module.allCases
            .filter { modules.contains($0) }
            .map { $0.rawValue }
            .joined(separator: ",")
    }
}

// MARK: - View

struct WatchScreenSettingsView: View {
    @Environment(\.theme) private var theme
    @StateObject private var model: WatchScreenSettingsModel

    /// Production initializer. Callers inject the push seam so the
    /// screen doesn't take a hard dependency on `HealthKitService` and
    /// tests can substitute a recorder.
    init(pusher: @escaping WatchScreenConfigPusher) {
        _model = StateObject(
            wrappedValue: WatchScreenSettingsModel(pusher: pusher)
        )
    }

    /// Preview / test initializer with a fully-constructed model.
    init(model: WatchScreenSettingsModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Form {
            presetSection
            modulesSection
        }
        .navigationTitle(
            String(
                localized: "settings.watchScreen.title",
                comment: "iOS Settings → Training → Watch in-workout screen nav title"
            )
        )
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var presetSection: some View {
        Section(
            header: Text(
                String(
                    localized: "settings.watchScreen.preset",
                    comment: "Watch screen preset picker section header"
                )
            )
        ) {
            Picker(
                selection: Binding<WatchScreenConfig.Preset>(
                    get: { model.preset },
                    set: { model.setPreset($0) }
                )
            ) {
                ForEach(WatchScreenConfig.Preset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            } label: {
                Label(
                    String(
                        localized: "settings.watchScreen.preset",
                        comment: "Watch screen preset picker label"
                    ),
                    systemImage: "square.grid.2x2"
                )
                .tint(theme.primary.primary)
            }
            .pickerStyle(.inline)
        }
    }

    private var modulesSection: some View {
        Section(
            header: Text(
                String(
                    localized: "settings.watchScreen.modules",
                    comment: "Watch screen module toggles section header"
                )
            )
        ) {
            ForEach(WatchScreenConfig.Module.allCases, id: \.self) { module in
                moduleRow(module)
            }
        }
    }

    @ViewBuilder
    private func moduleRow(_ module: WatchScreenConfig.Module) -> some View {
        let locked = WatchScreenConfig.lockedOnModules.contains(module)
        let isOn = model.enabledModules.contains(module)
        HStack(spacing: 8) {
            Label(module.displayName, systemImage: module.systemImage)
                .tint(theme.primary.primary)
            Spacer()
            if locked {
                Text(
                    String(
                        localized: "settings.watchScreen.locked",
                        comment: "Chip label on locked (mandatory) watch modules"
                    )
                )
                .font(.caption)
                .foregroundStyle(theme.neutrals.text3)
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
                    .disabled(true)
            } else {
                Toggle(
                    "",
                    isOn: Binding<Bool>(
                        get: { isOn },
                        set: { model.setModule(module, enabled: $0) }
                    )
                )
                .labelsHidden()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Localized display names

extension WatchScreenConfig.Preset {
    fileprivate var displayName: String {
        switch self {
        case .fullInfo:
            return String(
                localized: "settings.watchScreen.preset.fullInfo",
                comment: "Watch screen preset: full info (default)"
            )
        case .hrFocus:
            return String(
                localized: "settings.watchScreen.preset.hrFocus",
                comment: "Watch screen preset: HR focus"
            )
        case .list:
            return String(
                localized: "settings.watchScreen.preset.list",
                comment: "Watch screen preset: list"
            )
        case .nextFocus:
            return String(
                localized: "settings.watchScreen.preset.nextFocus",
                comment: "Watch screen preset: next set focus"
            )
        }
    }
}

extension WatchScreenConfig.Module {
    fileprivate var displayName: String {
        switch self {
        case .clock:
            return String(
                localized: "settings.watchScreen.module.clock",
                comment: "Watch module: clock"
            )
        case .elapsed:
            return String(
                localized: "settings.watchScreen.module.elapsed",
                comment: "Watch module: elapsed time"
            )
        case .setsTotal:
            return String(
                localized: "settings.watchScreen.module.setsTotal",
                comment: "Watch module: total sets counter"
            )
        case .heartRate:
            return String(
                localized: "settings.watchScreen.module.heartRate",
                comment: "Watch module: heart rate"
            )
        case .hrZone:
            return String(
                localized: "settings.watchScreen.module.hrZone",
                comment: "Watch module: heart rate zone"
            )
        case .hrAvgPeak:
            return String(
                localized: "settings.watchScreen.module.hrAvgPeak",
                comment: "Watch module: avg/peak heart rate"
            )
        case .nextSet:
            return String(
                localized: "settings.watchScreen.module.nextSet",
                comment: "Watch module: next set preview"
            )
        case .setDots:
            return String(
                localized: "settings.watchScreen.module.setDots",
                comment: "Watch module: set progress dots"
            )
        case .primaryAction:
            return String(
                localized: "settings.watchScreen.module.primaryAction",
                comment: "Watch module: primary action button"
            )
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .clock:         return "clock"
        case .elapsed:       return "timer"
        case .setsTotal:     return "number.square"
        case .heartRate:     return "heart.fill"
        case .hrZone:        return "gauge.medium"
        case .hrAvgPeak:     return "waveform.path.ecg"
        case .nextSet:       return "arrow.right.circle"
        case .setDots:       return "circle.grid.3x3.fill"
        case .primaryAction: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        WatchScreenSettingsView(pusher: { _ in })
    }
    .designThemePreview()
}

#Preview("HR Focus") {
    NavigationStack {
        WatchScreenSettingsView(
            model: WatchScreenSettingsModel(
                userDefaults: {
                    let defaults = UserDefaults(
                        suiteName: "watchScreen.preview.hrFocus"
                    ) ?? .standard
                    defaults.set(
                        WatchScreenConfig.Preset.hrFocus.rawValue,
                        forKey: WatchScreenSettingsModel.presetStorageKey
                    )
                    return defaults
                }(),
                pusher: { _ in }
            )
        )
    }
    .designThemePreview()
}
