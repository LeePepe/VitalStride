#if canImport(UIKit) && !os(macOS)

import DesignKit
import Testing

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
}

#endif
