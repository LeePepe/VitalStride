import SwiftUI
import Testing
@testable import DesignKit
#if canImport(AppKit)
import AppKit
#endif

@Suite("Strata semantic compatibility")
struct StrataTests {
    @Test func aliasesAndGeometry() {
        for dark in [false, true] {
            for seed in Seed.allCases {
                let theme = Theme(seed: seed, isDark: dark)
                #expect(theme.canvas == theme.neutrals.bg)
                #expect(theme.surface == theme.neutrals.card)
                #expect(theme.surfaceSubtle == theme.neutrals.inner)
                #expect(theme.inner == theme.surfaceSubtle)
                #expect(theme.accent == theme.primary.primary)
                #expect(theme.onAccent == theme.primary.onPrimary)
                #expect(theme.accentSubtle == theme.primary.primarySubtle)
                #expect(theme.critical == theme.danger)
                #expect(theme.foreground == theme.neutrals.text1)
                #expect(theme.secondaryForeground == theme.neutrals.text2)
                #expect(theme.tertiaryForeground == theme.neutrals.text3)
                #expect(theme.border == theme.neutrals.border)
            }
        }
        #expect(Theme().seed == .ocean)
        #expect(Radius.outer == 32 && Radius.card == 24 && Radius.control == 16 && Radius.pill == 999)
        #expect([Space.xxs, Space.xs, Space.sm, Space.md, Space.lg, Space.xl] == [4, 8, 12, 16, 24, 32])
    }
    @Test func oldSeedsKeepTheirDerivation() {
        for seed in Seed.allCases where seed != .ocean {
            for dark in [false, true] {
                #expect(Theme(seed: seed, isDark: dark).accent == makePrimaryPalette(seed: seed.color, isDark: dark).primary)
            }
        }
    }
    #if canImport(AppKit)
    @Test @MainActor func oceanResolvesExactPairedAccentAndContrast() throws {
        for dark in [false, true] {
            let theme = Theme(isDark: dark)
            let actual = try #require(NSColor(theme.accent).usingColorSpace(.sRGB))
            let expected = try #require(NSColor(Color(hex: dark ? "#6EC0F7" : "#0A6099")).usingColorSpace(.sRGB))
            #expect(abs(actual.redComponent - expected.redComponent) < 0.001)
            #expect(abs(actual.greenComponent - expected.greenComponent) < 0.001)
            #expect(abs(actual.blueComponent - expected.blueComponent) < 0.001)
            func luminance(_ color: NSColor) -> Double {
                func linear(_ value: CGFloat) -> Double { let v = Double(value); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
                return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
            }
            let foreground = try #require(NSColor(theme.onAccent).usingColorSpace(.sRGB))
            let a = luminance(actual), b = luminance(foreground)
            #expect((max(a, b) + 0.05) / (min(a, b) + 0.05) >= 4.5)
        }
    }
    @Test @MainActor func controlsRenderInBothModesAndTransparencyFallback() throws {
        for dark in [false, true] {
            for reduce in [false, true] {
                let content = VStack {
                    Card { Text("Legacy card") }
                    Card(header: { Text("Header") }, content: { Text("Body") })
                    Card(header: { Text("Header") }, content: { Text("Body") }, supporting: { Text("Support") })
                    Card(header: { Text("Header") }, content: { Text("Body") }, actions: { Text("Action") })
                    Card(header: { Text("Header") }, content: { Text("Body") }, supporting: { Text("Support") }, actions: { Text("Action") })
                    DesignButton("Continue", icon: "arrow.right") {}
                    DesignButton("Secondary", variant: .secondary, isDisabled: true) {}
                    DesignButton("Ghost", variant: .ghost, cornerRadius: Radius.pill) {}
                    DesignButton("Delete", variant: .destructive) {}
                    DesignButton("Loading", isLoading: true, fullWidth: true) {}
                    DesignSearchField("Search", text: .constant("demo"))
                    DesignTextField("Name", text: .constant(""))
                    DesignChip("Neutral")
                    DesignChip("Accent", tone: .accent)
                    DesignChip("Critical", tone: .critical)
                    DesignChip("Selected", isSelected: true, count: 2, onSelect: {}, onRemove: {})
                    DesignCheckbox(isOn: true) {}
                    DesignCheckbox(isOn: false) {}
                    DesignSegmentedBar(items: [(0, "A"), (1, "B")], selection: .constant(0))
                    DesignStateView(.empty, title: "Empty", message: "No items")
                    DesignStateView(.loading, title: "Loading", message: "Please wait")
                    DesignStateView(.error, title: "Retry", message: "Demo error", actionTitle: "Retry", action: {})
                    DesignDockedBar { Text("Dock") }
                }.padding().frame(width: 393).environment(\.theme, Theme(isDark: dark))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.designReduceTransparency, reduce)
                let renderer = ImageRenderer(content: content)
                #expect(try #require(renderer.nsImage).size.width == 393)
            }
        }
    }
    @Test @MainActor func interactiveControlsKeepMinimumHitArea() throws {
        func size<V: View>(_ view: V) throws -> CGSize {
            try #require(ImageRenderer(content: view).nsImage).size
        }
        for variant in [DesignButton.Variant.primary, .secondary, .ghost, .destructive] {
            #expect(try size(DesignButton("Go", variant: variant, minHeight: 1) {}).height >= 44)
        }
        #expect(try size(DesignCheckbox(isOn: false) {}).width == 44)
        #expect(try size(DesignCheckbox(isOn: true) {}).height == 44)
        #expect(try size(DesignTextField("Name", text: .constant(""))).height >= 44)
        #expect(try size(DesignSearchField("Search", text: .constant("query"))).height >= 44)
        #expect(try size(DesignChip("Select", onSelect: {})).height >= 44)
        #expect(try size(DesignChip("Remove", onRemove: {})).height >= 44)
        #expect(try size(DesignSegmentedBar(items: [(0, "A"), (1, "B")], selection: .constant(0))).height >= 44)
    }

    @Test @MainActor func reducedTransparencyRendersOpaqueThemeSurface() throws {
        for dark in [false, true] {
            let theme = Theme(isDark: dark)
            let content = Color.clear.frame(width: 100, height: 100)
                .designSurface(style: .glass)
                .environment(\.theme, theme)
                .environment(\.designReduceTransparency, true)
            let image = try #require(ImageRenderer(content: content).nsImage)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            let center = try #require(bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
            // Compare in the renderer's output color space: NSImage's TIFF
            // conversion can change raw sRGB component values in dark mode.
            let solid = Color.clear.frame(width: 100, height: 100)
                .designSurface(style: .solid)
                .environment(\.theme, theme)
            let solidImage = try #require(ImageRenderer(content: solid).nsImage)
            let solidData = try #require(solidImage.tiffRepresentation)
            let solidBitmap = try #require(NSBitmapImageRep(data: solidData))
            let expected = try #require(solidBitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
            #expect(center.alphaComponent == 1)
            #expect(abs(center.redComponent - expected.redComponent) < 0.001)
            #expect(abs(center.greenComponent - expected.greenComponent) < 0.001)
            #expect(abs(center.blueComponent - expected.blueComponent) < 0.001)
        }
    }
    #endif
}
