#if canImport(UIKit) && !os(macOS)

import DesignKit
import SwiftUI
import Testing
import UIKit
import XCTest

@testable import VitalStride

private func keyboardContrastRatio(_ foreground: UIColor, _ background: UIColor) -> Double? {
    func luminance(_ color: UIColor) -> Double? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }

        func linear(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    guard let foregroundLuminance = luminance(foreground),
          let backgroundLuminance = luminance(background) else {
        return nil
    }
    let lighter = max(foregroundLuminance, backgroundLuminance)
    let darker = min(foregroundLuminance, backgroundLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

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

    @Test("Interactive Done button colors meet WCAG AA for every seed and color scheme")
    @MainActor
    func interactiveAccentContrast() throws {
        for isDark in [false, true] {
            for seed in Seed.allCases {
                let theme = Theme(seed: seed, neutral: .slate, isDark: isDark)
                let ratio = try #require(
                    keyboardContrastRatio(
                        UIColor(theme.onInteractiveAccent),
                        UIColor(theme.interactiveAccent)
                    )
                )
                #expect(ratio >= 4.5)
            }
        }
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

@MainActor
final class WorkoutKeyboardUnitRenderingTests: XCTestCase {
    func testLightAndDarkKeyboardRender() {
        for isDark in [false, true] {
            let content = WorkoutNumericKeyboardContentView(
                field: .weight,
                setType: .working,
                exercise: nil,
                recentWeightKg: 40,
                theme: WorkoutNumericKeyboard.resolveTheme(isDark: isDark),
                onKeyPress: { _ in },
                onLeftAction: { _ in },
                onPresetReps: { _, _ in },
                onDone: {}
            )
            let host = UIHostingController(rootView: content)
            host.safeAreaRegions = []
            let size = CGSize(width: 375, height: WorkoutNumericKeyboard.preferredHeight())
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = isDark ? "Workout keyboard dark" : "Workout keyboard light"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(host.sizeThatFits(in: size).height, 0)
        }
    }
}

#endif
