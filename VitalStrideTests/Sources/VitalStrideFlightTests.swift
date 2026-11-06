import Foundation
import FlightKit
import SwiftUI
import Testing

@testable import VitalStride

@Suite("VitalStride Flight Tests")
@MainActor
struct VitalStrideFlightTests {
    @Test("Workout sidebar Scheme C is registered with a disabled default")
    func sidebarSchemeCDescriptor() {
        #expect(WorkoutFlight.sidebarSchemeC.key == "workout.active.sidebar_scheme_c")
        #expect(WorkoutFlight.sidebarSchemeC.defaultValue == false)
        #expect(WorkoutFlight.all.contains(WorkoutFlight.sidebarSchemeC))
    }

    @Test("Flight store environment carries the supplied shared store")
    func flightStoreEnvironment() {
        let defaults = UserDefaults(suiteName: "VitalStrideFlightTests.\(UUID().uuidString)")!
        let store = FlightStore(defaults: defaults)
        var values = EnvironmentValues()
        values.flightStore = store

        #expect(values.flightStore != nil)
        if let injectedStore = values.flightStore {
            #expect(injectedStore === store)
        }
        #expect(store.effectiveValue(for: WorkoutFlight.sidebarSchemeC) == false)
    }
}
