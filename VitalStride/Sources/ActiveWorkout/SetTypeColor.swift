// SetType label color for active-workout rows.
// Extracted from ActiveWorkoutView.swift (MY-874).

import SwiftUI
import VitalModels

extension SetType {
    var labelColor: Color {
        switch self {
        case .working: .primary
        case .warmup: .orange
        case .dropSet: .blue
        case .pyramid: .purple
        }
    }
}
