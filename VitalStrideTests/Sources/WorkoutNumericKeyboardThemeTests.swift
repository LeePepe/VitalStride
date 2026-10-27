#if canImport(UIKit) && !os(macOS)

import DesignKit
import SwiftUI
import Testing
import UIKit

@testable import VitalStride

@Suite("WorkoutNumericKeyboard.resolveTheme")
struct WorkoutNumericKeyboardThemeTests {
    @Test("Light theme uses teal seed, slate neutral, isDark false")
    func lightTheme() {
        let theme = WorkoutNumericKeyboard.resolveTheme(isDark: false)
        #expect(theme.seed == .teal)
        #expect(theme.neutral == .slate)
        #expect(theme.isDark == false)
    }

    @Test("Dark theme uses teal seed, slate neutral, isDark true")
    func darkTheme() {
        let theme = WorkoutNumericKeyboard.resolveTheme(isDark: true)
        #expect(theme.seed == .teal)
        #expect(theme.neutral == .slate)
        #expect(theme.isDark == true)
    }

    @Test("isDark parameter is passed through unchanged", arguments: [false, true])
    func isDarkPassThrough(_ isDark: Bool) {
        let theme = WorkoutNumericKeyboard.resolveTheme(isDark: isDark)
        #expect(theme.isDark == isDark)
    }

    @Test("Compact keyboard exposes the supported function actions")
    func compactFunctionActions() {
        #expect(LeftKeyAction.allCases.contains(.toggleUnilateral))
        #expect(LeftKeyAction.allCases.contains(.setWarmup))
        #expect(LeftKeyAction.allCases.contains(.toggleWeightUnit))
        #expect(LeftKeyAction.allCases.contains(.addDropSet))
        #expect(LeftKeyAction.allCases.contains(.addSet))
        #expect(LeftKeyAction.allCases.contains(.applyAISuggestion))
    }

    @Test("Rendered keyboard exposes the canonical kg/lb toggle label")
    @MainActor
    func renderedWeightUnitLabel() {
        let content = WorkoutNumericKeyboardContentView(
            field: .weight,
            setType: .working,
            exercise: nil,
            recentWeightKg: 40,
            theme: WorkoutNumericKeyboard.resolveTheme(isDark: false),
            onKeyPress: { _ in },
            onLeftAction: { _ in },
            onPresetReps: { _, _ in },
            onDone: {}
        )
        let host = UIHostingController(rootView: content)
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 280)
        host.view.layoutIfNeeded()

        #expect(WorkoutNumericKeyboardContentView.weightUnitToggleTitle() == "kg / lb")
        #expect(host.view.bounds.size == CGSize(width: 375, height: 280))
        #expect(host.sizeThatFits(in: host.view.bounds.size).height > 0)
    }
}

#endif
