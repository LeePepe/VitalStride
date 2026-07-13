// SetType label color for active-workout rows.
// Extracted from ActiveWorkoutView.swift (MY-874).
// Re-skinned to DesignKit theme tokens: each set type maps to a distinct,
// on-brand color routed through the resolved `Theme` instead of raw system
// colors. Call sites pass the environment theme in (see SubSetRow).

import DesignKit
import SwiftUI
import VitalModels

extension SetType {
    func labelColor(theme: Theme) -> Color {
        switch self {
        case .working: theme.primary.primary
        case .warmup: theme.warning
        case .dropSet: theme.chart(2)
        case .pyramid: theme.chart(4)
        }
    }
}
