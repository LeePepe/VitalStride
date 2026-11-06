import Foundation
import Testing
@testable import FlightKit

struct TestRemoteProvider: RemoteFlightProviding {
    let values: [String: Bool]

    func remoteValue(for key: String) -> Bool? {
        values[key]
    }
}

@Suite("FlightKit")
@MainActor
struct FlightKitTests {
    private let descriptor = FlightDescriptor(
        key: "workout.active.sidebar_scheme_c",
        title: "Sidebar scheme C",
        summary: "Use the horizontal exercise pill bar.",
        category: "Workout",
        defaultValue: false
    )

    @Test("local override wins over remote and default")
    func precedence() {
        let defaults = UserDefaults(suiteName: "FlightKitTests.precedence")!
        defaults.removePersistentDomain(forName: "FlightKitTests.precedence")
        let store = FlightStore(
            defaults: defaults,
            remoteProvider: TestRemoteProvider(values: [descriptor.key: false]),
            remoteEnabled: true
        )

        #expect(store.effectiveValue(for: descriptor) == false)
        store.setOverride(.forceOn, for: descriptor.key)
        #expect(store.effectiveValue(for: descriptor) == true)
        #expect(store.readout(for: descriptor).source == .localOverride)
    }

    @Test("remote value is used when enabled and no local override exists")
    func remotePrecedence() {
        let defaults = UserDefaults(suiteName: "FlightKitTests.remote")!
        defaults.removePersistentDomain(forName: "FlightKitTests.remote")
        let store = FlightStore(
            defaults: defaults,
            remoteProvider: TestRemoteProvider(values: [descriptor.key: true]),
            remoteEnabled: true
        )

        #expect(store.effectiveValue(for: descriptor))
        #expect(store.readout(for: descriptor).source == .remote)
    }

    @Test("overrides persist and reset-all clears them")
    func persistenceAndReset() {
        let suite = "FlightKitTests.persistence"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = FlightStore(defaults: defaults)
        first.setOverride(.forceOn, for: descriptor.key)

        let second = FlightStore(defaults: defaults)
        #expect(second.override(for: descriptor.key) == .forceOn)
        second.resetAll()
        #expect(second.override(for: descriptor.key) == .useDefault)
    }

    @Test("descriptor filtering and grouping are deterministic")
    func descriptorInputs() {
        let second = FlightDescriptor(
            key: "data.new",
            title: "New data",
            summary: "Data surface",
            category: "Data",
            defaultValue: true
        )
        #expect(FlightDescriptor.filtered([descriptor, second], query: "pill") == [descriptor])
        #expect(FlightDescriptor.grouped([descriptor, second])["Workout"] == [descriptor])
    }
}
