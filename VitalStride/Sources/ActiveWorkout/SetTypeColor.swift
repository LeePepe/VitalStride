// SetType label color for active-workout rows.
// Extracted from ActiveWorkoutView.swift (MY-874).
// Re-skinned to DesignKit theme tokens: each set type maps to a distinct,
// on-brand color routed through the resolved `Theme` instead of raw system
// colors. Call sites pass the environment theme in (see SubSetRow).

import DesignKit
import SwiftUI
import VitalModels

#if canImport(UIKit)
import UIKit
#endif

/// Solid system surfaces used by the workout content layer. Keep these separate
/// from Liquid Glass and DesignKit theme tokens so the logging surface follows
/// the platform appearance in both light and dark mode.
#if canImport(UIKit)
let workoutSystemGroupedBackground = Color(uiColor: .systemGroupedBackground)
let workoutSecondaryGroupedBackground = Color(uiColor: .secondarySystemGroupedBackground)
let workoutTertiaryFill = Color(uiColor: .tertiarySystemFill)
let workoutSeparator = Color(uiColor: .separator)
#elseif canImport(AppKit)
import AppKit
let workoutSystemGroupedBackground = Color(nsColor: .windowBackgroundColor)
let workoutSecondaryGroupedBackground = Color(nsColor: .underPageBackgroundColor)
let workoutTertiaryFill = Color(nsColor: .controlBackgroundColor)
let workoutSeparator = Color(nsColor: .separatorColor)
#endif

extension SetType {
    var semanticColor: Color {
        switch self {
        case .working: .secondary
        case .warmup, .dropSet: .orange
        case .pyramid: .indigo
        }
    }

    func labelColor(theme: Theme) -> Color {
        semanticColor
    }
}
