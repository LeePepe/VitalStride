// WorkoutKeyboardPrototype.swift — isolated SwiftUI visual prototype for the
// custom numeric keyboard rendered inside the ActiveWorkout weight/reps input.
//
// This prototype target intentionally does NOT import production modules
// (VitalStride / VitalModels / SwiftData / HealthKitService / AIService /
// VitalUI / UIKit). It duplicates the *minimum* shape of the production
// SetField / LeftKeyAction / PresetRepBucket enums so the visual layout can
// be iterated in the Xcode preview canvas + exported as light/dark shots for
// design review. Contract drift is contained: the migration stage (T017-04)
// is responsible for wiring the frozen visual over to the production
// keyboard using production types — this file is discarded at that point.
//
// Design tokens: DesignKit only (Theme / Space / Radius / TypeScale /
// primary palette + neutrals). No hardcoded colors, no magic numbers beyond
// the height/width frames enforced by the north-star.

import DesignKit
import SwiftUI

// MARK: - Mock enums (isolated from production)

/// Mirror of the production `SetField` shape — which field the keyboard is
/// currently editing. Only used by the preview to select a plausible layout.
private enum PrototypeSetField {
    case weight
    case weightRight
    case reps

    /// Integer-only fields (`reps`) suppress the decimal key slot; the digit
    /// grid renders a blank spacer in that cell.
    var isDecimalEnabled: Bool {
        switch self {
        case .weight, .weightRight: true
        case .reps: false
        }
    }
}

/// Mirror of the production `LeftKeyAction` shape — the 4 left-column
/// function keys. Enum order matches the production stack top-to-bottom.
private enum PrototypeLeftKeyAction: CaseIterable {
    case addPyramid
    case addDropSet
    case toggleUnilateral
    case copyToNext
}

/// Mirror of the production `PresetRepBucket` shape — 3 preset rep-range
/// buckets rendered as the top 3 keys of the right column.
private enum PrototypePresetBucket: CaseIterable {
    case high  // 15–20
    case mid   // 8–12
    case low   // 4–6

    var label: String {
        switch self {
        case .high: "15-20"
        case .mid: "8-12"
        case .low: "4-6"
        }
    }
}

/// Set-type mock: only the `working` distinction matters for the visual
/// enabled/disabled state on the left-column pyramid/drop-set keys.
private enum PrototypeSetType {
    case working
    case warmup
}

// MARK: - Prototype view

/// Prototype view for the workout numeric keyboard visual redesign.
///
/// Three-tier color hierarchy per north-star §11:
///   • Done         → `theme.primary.primary` fill + `onPrimary` text
///   • Preset keys  → `theme.primary.primarySubtle` fill + `primaryText`
///   • Function keys + digit keys → `theme.neutrals.inner` fill (recessed);
///                    digit-key foreground is `theme.neutrals.text1` (red-line;
///                    must never fall to text2/text3 — audit P0).
///
/// The container itself sits on `theme.neutrals.bg` with `Space.gap` (12)
/// column spacing and `Space.cardPadding` (16) outer padding.
public struct WorkoutKeyboardPrototype: View {
    private let field: PrototypeSetField
    private let setType: PrototypeSetType

    public init() {
        self.init(field: .weight, setType: .working)
    }

    fileprivate init(field: PrototypeSetField, setType: PrototypeSetType) {
        self.field = field
        self.setType = setType
    }

    public var body: some View {
        WorkoutKeyboardPrototypeContent(field: field, setType: setType)
    }
}

// MARK: - Internal content (theme-aware)

private struct WorkoutKeyboardPrototypeContent: View {
    @Environment(\.theme) private var theme
    let field: PrototypeSetField
    let setType: PrototypeSetType

    // Keyboard visual constants — mirror north-star §11 spec.
    private let columnSpacing: CGFloat = Space.gap      // 12
    private let rowSpacing: CGFloat = 8
    private let outerPadding: CGFloat = Space.cardPadding // 16
    private let sideColumnWidth: CGFloat = 76
    private let keyMinHeight: CGFloat = 44
    private let digitMinHeight: CGFloat = 52
    private let keyRadius: CGFloat = Radius.inner       // 10

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            leftColumn
                .frame(width: sideColumnWidth)
            centerColumn
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            rightColumn
                .frame(width: sideColumnWidth)
        }
        .padding(outerPadding)
        .background(theme.neutrals.bg)
        .accessibilityElement(children: .contain)
    }

    // MARK: Left column — function keys (recessed inner tier)

    private var leftColumn: some View {
        VStack(spacing: rowSpacing) {
            functionKey(.addPyramid, symbol: "arrow.up.to.line")
            functionKey(.addDropSet, symbol: "arrow.down.to.line")
            functionKey(.toggleUnilateral, text: "Uni/Total")
            functionKey(.copyToNext, text: "Copy")
        }
    }

    @ViewBuilder
    private func functionKey(_ action: PrototypeLeftKeyAction, symbol: String? = nil, text: String? = nil) -> some View {
        let enabled = isEnabled(action)
        HStack {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3)
                    .fontWeight(.medium)
            } else if let text {
                Text(text)
                    .font(TypeScale.meta)
                    .fontWeight(.medium)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: keyMinHeight)
        .foregroundStyle(enabled ? theme.neutrals.text2 : theme.neutrals.text3)
        .background(theme.neutrals.inner)
        .clipShape(RoundedRectangle(cornerRadius: keyRadius, style: .continuous))
    }

    private func isEnabled(_ action: PrototypeLeftKeyAction) -> Bool {
        switch action {
        case .addPyramid, .addDropSet: setType == .working
        case .toggleUnilateral, .copyToNext: true
        }
    }

    // MARK: Center column — digit grid (numbers = text1 red-line)

    private var centerColumn: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: rowSpacing), count: 3)
        return LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(1...9, id: \.self) { digit in
                digitKey(label: "\(digit)")
            }
            decimalKeySlot
            digitKey(label: "0")
            digitKey(label: "⌫", isDelete: true)
        }
    }

    @ViewBuilder
    private var decimalKeySlot: some View {
        if field.isDecimalEnabled {
            digitKey(label: ".")
        } else {
            Color.clear
                .frame(minHeight: digitMinHeight)
                .accessibilityHidden(true)
        }
    }

    private func digitKey(label: String, isDelete: Bool = false) -> some View {
        Text(label)
            .font(TypeScale.title)
            .fontWeight(.medium)
            .monospacedDigit()
            // Red-line: digit keys must use text1. Delete key softens to text2.
            .foregroundStyle(isDelete ? theme.neutrals.text2 : theme.neutrals.text1)
            .frame(maxWidth: .infinity, minHeight: digitMinHeight)
            .background(theme.neutrals.inner)
            .clipShape(RoundedRectangle(cornerRadius: keyRadius, style: .continuous))
    }

    // MARK: Right column — preset reps (primarySubtle) + Done (primary)

    private var rightColumn: some View {
        VStack(spacing: rowSpacing) {
            ForEach(PrototypePresetBucket.allCases, id: \.self) { bucket in
                presetKey(bucket)
            }
            doneKey
        }
    }

    private func presetKey(_ bucket: PrototypePresetBucket) -> some View {
        Text(bucket.label)
            .font(TypeScale.body)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(theme.primary.primaryText)
            .frame(maxWidth: .infinity, minHeight: keyMinHeight)
            .background(theme.primary.primarySubtle)
            .clipShape(RoundedRectangle(cornerRadius: keyRadius, style: .continuous))
    }

    private var doneKey: some View {
        Text("Done")
            .font(TypeScale.title)
            .fontWeight(.semibold)
            .foregroundStyle(theme.primary.onPrimary)
            .frame(maxWidth: .infinity, minHeight: keyMinHeight)
            .background(theme.primary.primary)
            .clipShape(RoundedRectangle(cornerRadius: keyRadius, style: .continuous))
    }
}

// MARK: - Previews (light/dark × phone/pad)

#Preview("iPhone Light") {
    WorkoutKeyboardPrototype(field: .weight, setType: .working)
        .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: false))
        .frame(width: 393, height: 260)
        .background(Theme(seed: .teal, neutral: .slate, isDark: false).neutrals.bg)
}

#Preview("iPhone Dark") {
    WorkoutKeyboardPrototype(field: .weight, setType: .working)
        .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: true))
        .frame(width: 393, height: 260)
        .background(Theme(seed: .teal, neutral: .slate, isDark: true).neutrals.bg)
        .environment(\.colorScheme, .dark)
}

#Preview("iPad Light") {
    WorkoutKeyboardPrototype(field: .weight, setType: .working)
        .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: false))
        .frame(width: 1024, height: 280)
        .background(Theme(seed: .teal, neutral: .slate, isDark: false).neutrals.bg)
}

#Preview("iPad Dark") {
    WorkoutKeyboardPrototype(field: .reps, setType: .warmup)
        .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: true))
        .frame(width: 1024, height: 280)
        .background(Theme(seed: .teal, neutral: .slate, isDark: true).neutrals.bg)
        .environment(\.colorScheme, .dark)
}

