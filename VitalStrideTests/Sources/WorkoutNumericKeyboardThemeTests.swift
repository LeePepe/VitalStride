#if canImport(UIKit) && !os(macOS)

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

@Suite("WorkoutNumericKeyboard native semantic styling")
struct WorkoutNumericKeyboardThemeTests {
    @Test("Dock background resolves from secondarySystemBackground in both appearances")
    @MainActor
    func nativeDockBackgroundAdaptsToTraits() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let keyboard = WorkoutNumericKeyboard(frame: CGRect(x: 0, y: 0, width: 393, height: 280))
            keyboard.overrideUserInterfaceStyle = style
            let window = UIWindow(frame: keyboard.bounds)
            window.overrideUserInterfaceStyle = style
            window.addSubview(keyboard)
            window.makeKeyAndVisible()
            keyboard.layoutIfNeeded()
            window.layoutIfNeeded()

            let traits = UITraitCollection(userInterfaceStyle: style)
            let expected = UIColor.secondarySystemBackground.resolvedColor(with: traits)
            #expect(keyboard.backgroundColor?.resolvedColor(with: traits) == expected)
            #expect(keyboard.hostingController?.view.backgroundColor?.resolvedColor(with: traits) == expected)
            window.isHidden = true
        }
    }

    @Test("Native Done button colors meet WCAG AA in both color schemes")
    @MainActor
    func doneButtonContrast() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let ratio = try #require(
                keyboardContrastRatio(
                    WorkoutNumericKeyboardContentView.doneButtonForegroundUIColor,
                    WorkoutNumericKeyboardContentView.doneButtonBackgroundUIColor.resolvedColor(with: traits)
                )
            )
            #expect(ratio >= 4.5)
        }
    }

    @Test("Compact keyboard exposes the supported function actions")
    func compactFunctionActions() {
        #expect(LeftKeyAction.allCases.contains(.toggleUnilateral))
        #expect(LeftKeyAction.allCases.contains(.setWarmup))
        #expect(LeftKeyAction.allCases.contains(.copyToNext))
        #expect(LeftKeyAction.allCases.contains(.toggleWeightUnit))
        #expect(LeftKeyAction.allCases.contains(.addDropSet))
        #expect(LeftKeyAction.allCases.contains(.addSet))
        #expect(LeftKeyAction.allCases.contains(.applyAISuggestion))
        #expect(NumericKeypad.totalGridHeight == 232)
    }

    @Test("Rendered keyboard exposes the canonical kg/lb toggle label")
    @MainActor
    func renderedWeightUnitLabel() {
        let content = WorkoutNumericKeyboardContentView(
            field: .weight,
            setType: .working,
            exercise: nil,
            recentWeightKg: 40,
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
    func testKeyboardDockHasNoTopOrBottomSlicingStripsInLightAndDark() throws {
        for isDark in [false, true] {
            let heights = [CGFloat(280), WorkoutNumericKeyboard.preferredHeight()]
            for height in heights {
                let keyboard = WorkoutNumericKeyboard(frame: CGRect(x: 0, y: 0, width: 393, height: height))
                keyboard.overrideUserInterfaceStyle = isDark ? .dark : .light
                let window = UIWindow(frame: keyboard.bounds)
                window.overrideUserInterfaceStyle = isDark ? .dark : .light
                window.addSubview(keyboard)
                window.makeKeyAndVisible()
                keyboard.layoutIfNeeded()
                window.layoutIfNeeded()

                XCTAssertEqual(
                    keyboard.backgroundColor?.resolvedColor(with: keyboard.traitCollection),
                    UIColor.secondarySystemBackground.resolvedColor(with: keyboard.traitCollection)
                )
                XCTAssertEqual(
                    keyboard.hostingController?.view.backgroundColor?.resolvedColor(with: keyboard.traitCollection),
                    UIColor.secondarySystemBackground.resolvedColor(with: keyboard.traitCollection)
                )
                XCTAssertEqual(keyboard.hostingController?.safeAreaRegions.isEmpty, true)

                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let image = UIGraphicsImageRenderer(size: keyboard.bounds.size, format: format).image { _ in
                    keyboard.drawHierarchy(in: keyboard.bounds, afterScreenUpdates: true)
                }
                guard let cgImage = image.cgImage else {
                    XCTFail("Unable to read rendered keyboard pixels")
                    continue
                }
                let imageWidth = Int(image.size.width)
                let imageHeight = Int(image.size.height)
                let bytesPerRow = imageWidth * 4
                var pixels = [UInt8](repeating: 0, count: imageHeight * bytesPerRow)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(
                    data: &pixels,
                    width: imageWidth,
                    height: imageHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    XCTFail("Unable to create pixel sampling context")
                    continue
                }
                context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))

                func rgb(at point: CGPoint) -> (CGFloat, CGFloat, CGFloat)? {
                    let x = Int(point.x)
                    let y = Int(point.y)
                    guard x >= 0, y >= 0, x < imageWidth, y < imageHeight else { return nil }
                    let offset = y * bytesPerRow + x * 4
                    return (CGFloat(pixels[offset]) / 255, CGFloat(pixels[offset + 1]) / 255, CGFloat(pixels[offset + 2]) / 255)
                }

                func uicolorRGB(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat) {
                    var red: CGFloat = 0
                    var green: CGFloat = 0
                    var blue: CGFloat = 0
                    var alpha: CGFloat = 0
                    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    return (red, green, blue)
                }

                let resolvedBackground = UIColor.secondarySystemBackground.resolvedColor(with: keyboard.traitCollection)
                let background = uicolorRGB(resolvedBackground)
                if let top = rgb(at: CGPoint(x: 20, y: 0)) {
                    XCTAssertLessThanOrEqual(max(abs(top.0 - background.0), abs(top.1 - background.1), abs(top.2 - background.2)), 32 / 255, "top=\(top) background=\(background)")
                }
                for point in [CGPoint(x: 20, y: 2), CGPoint(x: 20, y: height - 2)] {
                    guard let pixel = rgb(at: point) else { continue }
                    XCTAssertLessThanOrEqual(max(abs(pixel.0 - background.0), abs(pixel.1 - background.1), abs(pixel.2 - background.2)), 6 / 255, "point=\(point) pixel=\(pixel) background=\(background)")
                }
                window.isHidden = true
            }
        }
    }

    func testLightAndDarkKeyboardRender() {
        var renderedCornerPixels: [(UInt8, UInt8, UInt8)] = []

        for isDark in [false, true] {
            let content = WorkoutNumericKeyboardContentView(
                field: .weight,
                setType: .working,
                exercise: nil,
                recentWeightKg: 40,
                onKeyPress: { _ in },
                onLeftAction: { _ in },
                onPresetReps: { _, _ in },
                onDone: {}
            )
            .environment(\.colorScheme, isDark ? .dark : .light)
            let host = UIHostingController(rootView: content)
            host.overrideUserInterfaceStyle = isDark ? .dark : .light
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

            guard let cgImage = image.cgImage,
                  let provider = cgImage.dataProvider,
                  let data = provider.data as Data? else {
                XCTFail("Unable to read rendered keyboard pixels")
                continue
            }
            let bytes = [UInt8](data)
            let offset = 1 * cgImage.bytesPerRow + 1 * 4
            renderedCornerPixels.append((bytes[offset], bytes[offset + 1], bytes[offset + 2]))
        }

        XCTAssertEqual(renderedCornerPixels.count, 2)
        if renderedCornerPixels.count == 2 {
            XCTAssertTrue(
                renderedCornerPixels[0].0 != renderedCornerPixels[1].0 ||
                renderedCornerPixels[0].1 != renderedCornerPixels[1].1 ||
                renderedCornerPixels[0].2 != renderedCornerPixels[1].2
            )
        }
    }
}

#endif
