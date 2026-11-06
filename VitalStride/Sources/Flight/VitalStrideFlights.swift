import FlightKit
import SwiftUI

enum WorkoutFlight {
    static let sidebarSchemeC = FlightDescriptor(
        key: "workout.active.sidebar_scheme_c",
        title: String(localized: "flight.workout.sidebarSchemeC.title", comment: "Flight flag title"),
        summary: String(localized: "flight.workout.sidebarSchemeC.summary", comment: "Flight flag summary"),
        category: "Workout",
        defaultValue: false
    )

    static let all: [FlightDescriptor] = [sidebarSchemeC]
}

private struct FlightStoreKey: EnvironmentKey {
    static let defaultValue: FlightStore? = nil
}

extension EnvironmentValues {
    var flightStore: FlightStore? {
        get { self[FlightStoreKey.self] }
        set { self[FlightStoreKey.self] = newValue }
    }
}
