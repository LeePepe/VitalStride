import Foundation
import HealthKitService
import Testing

@testable import VitalStride

// MARK: - Test double for the WC push seam

/// Actor-serialized recorder for pushed `WatchScreenConfig` values. Lets
/// tests assert what the settings model sent through the injected seam
/// without spinning up `WCSession`.
private actor PushRecorder {
    private(set) var configs: [WatchScreenConfig] = []

    func append(_ config: WatchScreenConfig) {
        configs.append(config)
    }

    var count: Int { configs.count }
    var latest: WatchScreenConfig? { configs.last }
}

// MARK: - Helpers

/// Build a fresh, isolated UserDefaults suite for each test so persistence
/// assertions don't bleed between cases or into the app's real store.
private func makeTestDefaults(_ suite: String = UUID().uuidString) -> UserDefaults {
    let name = "watchScreen.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

// MARK: - Suite

@MainActor
@Suite("Watch Screen Settings")
struct WatchScreenSettingsTests {

    // MARK: Defaults

    @Test("Default state: fullInfo preset + all modules on")
    func defaultState() {
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            pusher: { _ in }
        )
        #expect(model.preset == .fullInfo)
        #expect(model.enabledModules == Set(WatchScreenConfig.Module.allCases))
    }

    @Test("Empty UserDefaults decodes to default state")
    func emptyStorageDecodesToDefault() {
        let stored = WatchScreenSettingsModel.load(from: makeTestDefaults())
        #expect(stored.preset == .fullInfo)
        #expect(stored.enabledModules == Set(WatchScreenConfig.Module.allCases))
    }

    // MARK: Persistence — presets

    @Test(
        "All presets round-trip through UserDefaults",
        arguments: WatchScreenConfig.Preset.allCases
    )
    func persistAllPresets(_ preset: WatchScreenConfig.Preset) {
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            pusher: { _ in }
        )
        model.setPreset(preset)
        #expect(defaults.string(forKey: WatchScreenSettingsModel.presetStorageKey) == preset.rawValue)

        let reloaded = WatchScreenSettingsModel.load(from: defaults)
        #expect(reloaded.preset == preset)
    }

    @Test("Malformed preset falls back to fullInfo")
    func malformedPresetFallsBack() {
        let defaults = makeTestDefaults()
        defaults.set("not-a-preset", forKey: WatchScreenSettingsModel.presetStorageKey)
        let stored = WatchScreenSettingsModel.load(from: defaults)
        #expect(stored.preset == .fullInfo)
    }

    // MARK: Persistence — modules

    @Test("Persist a partial module set and reload")
    func persistModules() {
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            pusher: { _ in }
        )
        model.setModule(.clock, enabled: false)
        model.setModule(.hrZone, enabled: false)

        let reloaded = WatchScreenSettingsModel.load(from: defaults)
        #expect(!reloaded.enabledModules.contains(.clock))
        #expect(!reloaded.enabledModules.contains(.hrZone))
        // Locked-on modules must still be present.
        #expect(reloaded.enabledModules.contains(.heartRate))
        #expect(reloaded.enabledModules.contains(.primaryAction))
    }

    @Test("Malformed modules string falls back to all-on")
    func malformedModulesFallsBack() {
        let defaults = makeTestDefaults()
        defaults.set("garbage,tokens,only", forKey: WatchScreenSettingsModel.modulesStorageKey)
        let stored = WatchScreenSettingsModel.load(from: defaults)
        #expect(stored.enabledModules == Set(WatchScreenConfig.Module.allCases))
    }

    @Test("Empty modules string falls back to all-on")
    func emptyModulesFallsBack() {
        let defaults = makeTestDefaults()
        defaults.set("", forKey: WatchScreenSettingsModel.modulesStorageKey)
        let stored = WatchScreenSettingsModel.load(from: defaults)
        #expect(stored.enabledModules == Set(WatchScreenConfig.Module.allCases))
    }

    @Test("Partially-unknown module tokens keep the known ones")
    func partiallyUnknownModulesKept() {
        let defaults = makeTestDefaults()
        defaults.set(
            "clock,mysteryModule,heartRate,anotherJunk",
            forKey: WatchScreenSettingsModel.modulesStorageKey
        )
        let stored = WatchScreenSettingsModel.load(from: defaults)
        #expect(stored.enabledModules.contains(.clock))
        #expect(stored.enabledModules.contains(.heartRate))
        // Unknown tokens must not somehow become real modules.
        #expect(stored.enabledModules.count >= 2)
    }

    // MARK: Locked-on invariant

    @Test(
        "Locked-on modules cannot be disabled through setModule",
        arguments: Array(WatchScreenConfig.lockedOnModules)
    )
    func lockedModuleCannotBeDisabled(_ locked: WatchScreenConfig.Module) {
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            pusher: { _ in }
        )
        model.setModule(locked, enabled: false)
        #expect(model.enabledModules.contains(locked))
    }

    @Test("currentConfig always contains locked-on modules")
    func currentConfigEnforcesLocked() {
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            pusher: { _ in }
        )
        // Disable everything we can.
        for module in WatchScreenConfig.Module.allCases {
            model.setModule(module, enabled: false)
        }
        let config = model.currentConfig
        #expect(config.enabledModules.contains(.heartRate))
        #expect(config.enabledModules.contains(.primaryAction))
    }

    // MARK: Push seam

    @Test("Changing the preset pushes the full config through the seam")
    func presetChangePushesConfig() async {
        let recorder = PushRecorder()
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            now: { Date(timeIntervalSince1970: 42) },
            pusher: { config in await recorder.append(config) }
        )
        let task = model.setPreset(.hrFocus)
        await task.value

        let count = await recorder.count
        let latest = await recorder.latest
        #expect(count == 1)
        #expect(latest?.preset == .hrFocus)
        #expect(latest?.enabledModules.contains(.heartRate) == true)
        #expect(latest?.enabledModules.contains(.primaryAction) == true)
        #expect(latest?.updatedAt == Date(timeIntervalSince1970: 42))
    }

    @Test("Toggling an unlocked module pushes the updated set")
    func moduleTogglePushesConfig() async {
        let recorder = PushRecorder()
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            pusher: { config in await recorder.append(config) }
        )
        await model.setModule(.clock, enabled: false).value

        let latest = await recorder.latest
        #expect(latest?.enabledModules.contains(.clock) == false)
        // Locked-on still present after the push.
        #expect(latest?.enabledModules.contains(.heartRate) == true)
        #expect(latest?.enabledModules.contains(.primaryAction) == true)
    }

    @Test("Toggling a locked-on module does not fire a push")
    func lockedToggleNoOpNoPush() async {
        let recorder = PushRecorder()
        let defaults = makeTestDefaults()
        let model = WatchScreenSettingsModel(
            userDefaults: defaults,
            pusher: { config in await recorder.append(config) }
        )
        await model.setModule(.heartRate, enabled: false).value
        await model.setModule(.primaryAction, enabled: false).value

        let count = await recorder.count
        #expect(count == 0)
    }
}
