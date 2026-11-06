import Foundation
import Observation

@MainActor
@Observable
public final class FlightStore {
    public static let defaultSuiteName = "com.shared.flightkit.overrides"

    private let defaults: UserDefaults
    private let remoteProvider: any RemoteFlightProviding
    private let remoteEnabled: Bool
    private var overrides: [String: FlightOverrideState]

    public init(
        defaults: UserDefaults? = nil,
        remoteProvider: any RemoteFlightProviding = DefaultRemoteFlightProvider(),
        remoteEnabled: Bool = false
    ) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.defaultSuiteName) ?? .standard
        self.remoteProvider = remoteProvider
        self.remoteEnabled = remoteEnabled
        self.overrides = Self.loadOverrides(from: self.defaults)
    }

    public var isRemoteEnabled: Bool { remoteEnabled }

    public func override(for key: String) -> FlightOverrideState {
        overrides[key] ?? .useDefault
    }

    public func setOverride(_ state: FlightOverrideState, for key: String) {
        if state == .useDefault {
            overrides.removeValue(forKey: key)
        } else {
            overrides[key] = state
        }
        persistOverrides()
    }

    public func clearOverride(for key: String) {
        setOverride(.useDefault, for: key)
    }

    public func resetAll() {
        overrides.removeAll()
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    public func remoteValue(for descriptor: FlightDescriptor) -> Bool? {
        guard remoteEnabled else { return nil }
        return remoteProvider.remoteValue(for: descriptor.key)
    }

    public func readout(for descriptor: FlightDescriptor) -> FlightReadout {
        let remote = remoteValue(for: descriptor)
        let state = override(for: descriptor.key)
        if let localValue = state.value {
            return FlightReadout(
                value: localValue,
                source: .localOverride,
                remoteValue: remote,
                defaultValue: descriptor.defaultValue
            )
        }
        if let remote {
            return FlightReadout(
                value: remote,
                source: .remote,
                remoteValue: remote,
                defaultValue: descriptor.defaultValue
            )
        }
        return FlightReadout(
            value: descriptor.defaultValue,
            source: .default,
            remoteValue: remote,
            defaultValue: descriptor.defaultValue
        )
    }

    public func effectiveValue(for descriptor: FlightDescriptor) -> Bool {
        readout(for: descriptor).value
    }

    private static let defaultsKey = "flightkit.overrides"

    private static func loadOverrides(from defaults: UserDefaults) -> [String: FlightOverrideState] {
        guard let values = defaults.dictionary(forKey: defaultsKey) else { return [:] }
        return values.reduce(into: [:]) { result, entry in
            guard let rawValue = entry.value as? String,
                  let state = FlightOverrideState(rawValue: rawValue),
                  state != .useDefault
            else { return }
            result[entry.key] = state
        }
    }

    private func persistOverrides() {
        defaults.set(
            overrides.mapValues(\.rawValue),
            forKey: Self.defaultsKey
        )
    }
}
