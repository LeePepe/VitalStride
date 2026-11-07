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

    static let focusModeDefault = FlightDescriptor(
        key: "workout.active.focus_mode_default",
        title: String(localized: "flight.workout.focusModeDefault.title", defaultValue: "Focus Mode Default", comment: "Flight flag title for default active workout focus mode"),
        summary: String(localized: "flight.workout.focusModeDefault.summary", defaultValue: "Start active workouts in Focus Now mode by default", comment: "Flight flag summary for default active workout focus mode"),
        category: "Workout",
        defaultValue: false
    )

    static let all: [FlightDescriptor] = [sidebarSchemeC, focusModeDefault]
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
