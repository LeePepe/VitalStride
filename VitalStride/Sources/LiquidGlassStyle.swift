// Shared visual helpers for the redesigned Exercise Picker / Active Workout
// surfaces. Two pieces live here so they have a single source of truth across
// `ExercisePickerView`, `SetRow`, and `ActiveWorkoutView`:
//
//  1. Gated Liquid Glass backgrounds (`liquidGlassBar` / `liquidGlassCapsule`).
//     `.glassEffect(...)` only exists on the iOS 26 / macOS 26 SDKs; the app
//     deploys to iOS 18, so the API is availability-gated and falls back to the
//     DesignKit flat card / inner fill below 26 so nothing breaks. The glass
//     panel must be attached to the grid via `.safeAreaBar`/`.overlay`, never
//     `.safeAreaInset` — see `FloatingPanelAttachment` for why.
//  2. `categoryColor(_:theme:)` — a SEED-hued categorical color family (a tight
//     blue-ward hue fan at stepped brightness). Ported from the approved
//     prototype's ProtoKit. Never green / amber / red so the semantic
//     success-green / warning-orange / danger-red stay unique.

import DesignKit
import SwiftUI
import VitalModels

extension View {
    /// Gated Liquid Glass surface for the floating filter bar. Uses iOS 26
    /// `.glassEffect`; falls back to a flat DesignKit card + hairline below 26.
    ///
    /// The panel is attached to the card grid with `.safeAreaBar` (iOS 26) /
    /// non-layout `.overlay` (iOS 18) — see `FloatingPanelAttachment`. It must
    /// NOT be attached with `.safeAreaInset`, whose inset resolves *inside* the
    /// grid's lazy placement pass and never converges, pinning the main thread
    /// at 100% CPU. With the bar/overlay attachment the glass surface is
    /// layout-stable.
    @ViewBuilder
    func liquidGlassBar(theme: Theme, cornerRadius: CGFloat = 0) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(theme.neutrals.card)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Gated Liquid Glass capsule for floating capsule chrome (index bar).
    /// Falls back to a translucent DesignKit inner fill + hairline below 26.
    @ViewBuilder
    func liquidGlassCapsule(theme: Theme) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(theme.neutrals.inner.opacity(0.85))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.neutrals.border, lineWidth: 1))
        }
    }
}

// MARK: - Categorical color (SEED-hued family, NOT rainbow)

/// Categorical distinction that walks the seed hue in a tight blue-ward band at
/// stepped saturation / brightness — never green / amber / red, so the semantic
/// success / warning / danger colors stay reserved. Ported verbatim from the
/// approved prototype's `ProtoKit.categoryColor`.
func categoryColor(_ index: Int, theme: Theme) -> Color {
    let seedHue = hsbHue(theme.seed.color) * 360
    let hueOffsets: [Double] = [0, 14, 28, 8, 20]
    let brightSteps: [Double] = [0, -0.10, 0.10, -0.05, 0.06]
    let count = hueOffsets.count
    let h = ((seedHue + hueOffsets[index % count])
        .truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360) / 360
    let base = theme.isDark ? 0.82 : 0.58
    let brightness = max(0.30, min(0.95, base + brightSteps[index % count]))
    return Color(hue: h, saturation: theme.isDark ? 0.55 : 0.70, brightness: brightness)
}

/// Stable 0..4 category index for an `Equipment`, so each equipment tile draws
/// a consistent seed-hued color regardless of the filtered section order.
func categoryColorIndex(for equipment: Equipment) -> Int {
    (Equipment.allCases.firstIndex(of: equipment) ?? 0) % 5
}
