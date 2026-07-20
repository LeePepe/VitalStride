import SwiftUI

// ============================================================================
//  Theme — a resolved token set for the current (seed, neutral, colorScheme).
//  Inject via .designTheme(seed:neutral:); read with @Environment(\.theme).
//  This is the SwiftUI equivalent of the web CSS-variable set.
// ============================================================================

public struct Theme: Sendable {
    public let seed: Seed
    public let neutral: Neutral
    public let isDark: Bool

    public let primary: PrimaryPalette
    public let neutrals: Neutrals
    public let charts: [Color]

    public var success: Color { Semantic.success(isDark: isDark) }
    public var warning: Color { Semantic.warning(isDark: isDark) }
    public var danger: Color { Semantic.danger(isDark: isDark) }

    public init(seed: Seed = .blue, neutral: Neutral = .slate, isDark: Bool = false) {
        self.seed = seed
        self.neutral = neutral
        self.isDark = isDark
        self.primary = makePrimaryPalette(seed: seed.color, isDark: isDark)
        self.neutrals = neutral.palette(isDark: isDark)
        self.charts = chartPalette(seed: seed.color, isDark: isDark)
    }

    /// Chart color by index, wrapping the 8-stop palette.
    public func chart(_ i: Int) -> Color { charts[i % charts.count] }
}

// MARK: - Design tokens (shape, spacing, type) — one language, all platforms

public enum Radius {
    public static let card: CGFloat = 14
    public static let inner: CGFloat = 10
}

public enum Space {
    public static let cardPadding: CGFloat = 16
    public static let gap: CGFloat = 12
    public static let contentMaxWidth: CGFloat = 1200
}

public enum TypeScale {
    public static let display = Font.system(size: 26, weight: .semibold).monospacedDigit()
    public static let title = Font.system(size: 16, weight: .semibold)
    public static let body = Font.system(size: 14)
    public static let meta = Font.system(size: 12)
    public static let num = Font.system(size: 14).monospacedDigit()
    public static let metricXL = Font.system(size: 44, weight: .semibold).monospacedDigit()
    public static let metricXXL = Font.system(size: 64, weight: .semibold).monospacedDigit()
}

// MARK: - Environment plumbing

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

public extension View {
    /// Resolve the theme from a (seed, neutral) + the current colorScheme.
    func designTheme(seed: Seed = .blue, neutral: Neutral = .slate) -> some View {
        modifier(ThemeResolver(seed: seed, neutral: neutral))
    }

    /// Convenience for `#Preview` blocks: applies the app's default theme
    /// (teal / slate) plus page padding so previews render like production.
    /// Use in previews of any view that reads `@Environment(\.theme)`.
    func designThemePreview(seed: Seed = .teal, neutral: Neutral = .slate) -> some View {
        modifier(ThemeResolver(seed: seed, neutral: neutral))
    }
}

private struct ThemeResolver: ViewModifier {
    let seed: Seed
    let neutral: Neutral
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = Theme(seed: seed, neutral: neutral, isDark: scheme == .dark)
        content
            .environment(\.theme, theme)
            .background(theme.neutrals.bg)
            .foregroundStyle(theme.neutrals.text1)
    }
}
