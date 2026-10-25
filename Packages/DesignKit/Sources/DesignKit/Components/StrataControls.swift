import SwiftUI

public enum DesignSurfaceStyle: Sendable { case solid, glass }

// SwiftUI exposes the system preference as read-only. This internal override
// lets package tests exercise its opaque branch without changing macOS settings.
private struct DesignReduceTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var designReduceTransparency: Bool {
        get { self[DesignReduceTransparencyKey.self] }
        set { self[DesignReduceTransparencyKey.self] = newValue }
    }
}

private struct DesignSurface: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.designReduceTransparency) private var forceSolid
    let style: DesignSurfaceStyle
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content
            .background {
                if style == .glass && !reduceTransparency && !forceSolid {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.regularMaterial)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(theme.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(theme.border, lineWidth: 1))
    }
}

public extension View {
    func designSurface(style: DesignSurfaceStyle = .solid, cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(DesignSurface(style: style, cornerRadius: cornerRadius))
    }
}

public struct DesignButton: View {
    public enum Variant: Sendable { case primary, secondary, ghost, destructive }
    @Environment(\.theme) private var theme
    private let title: String
    private let variant: Variant
    private let icon: String?
    private let isLoading: Bool
    private let isDisabled: Bool
    private let fullWidth: Bool
    private let minHeight: CGFloat
    private let cornerRadius: CGFloat
    private let action: () -> Void

    public init(_ title: String, variant: Variant = .primary, icon: String? = nil,
                isLoading: Bool = false, isDisabled: Bool = false, fullWidth: Bool = false,
                cornerRadius: CGFloat = Radius.control, minHeight: CGFloat = Space.minTapTarget, action: @escaping () -> Void) {
        self.title = title; self.variant = variant; self.icon = icon
        self.isLoading = isLoading; self.isDisabled = isDisabled; self.fullWidth = fullWidth
        self.cornerRadius = cornerRadius
        self.minHeight = max(Space.minTapTarget, minHeight); self.action = action
    }
    private var foreground: Color {
        switch variant {
        case .primary: theme.onAccent
        case .destructive: theme.critical
        case .secondary, .ghost: theme.accent
        }
    }
    private var background: Color {
        switch variant {
        case .primary: theme.accent
        case .secondary, .destructive: theme.inner
        case .ghost: .clear
        }
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if isLoading { ProgressView().controlSize(.small).tint(foreground).accessibilityHidden(true) }
                else if let icon { Image(systemName: icon).accessibilityHidden(true) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .padding(.horizontal, Space.md)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

public struct DesignTextField: View {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    private let title: String
    @Binding private var text: String
    private let icon: String?
    private let clearLabel: String
    public init(_ title: String, text: Binding<String>, icon: String? = nil,
                clearLabel: String = String(localized: "Clear", comment: "Clear input")) {
        self.title = title; self._text = text; self.icon = icon; self.clearLabel = clearLabel
    }
    public var body: some View {
        HStack(spacing: Space.xs) {
            if let icon { Image(systemName: icon).foregroundStyle(theme.secondaryForeground).accessibilityHidden(true) }
            TextField(title, text: $text).textFieldStyle(.plain).focused($focused).accessibilityLabel(title)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: Space.minTapTarget, height: Space.minTapTarget)
                }.buttonStyle(.plain).accessibilityLabel(clearLabel)
            }
        }
        .padding(.leading, Space.sm).padding(.trailing, text.isEmpty ? Space.sm : 0)
        .frame(minHeight: Space.minTapTarget)
        .background(theme.inner, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(focused ? theme.accent : theme.border, lineWidth: 1))
    }
}

public struct DesignSearchField: View {
    private let title: String
    @Binding private var text: String
    public init(_ title: String, text: Binding<String>) { self.title = title; self._text = text }
    public var body: some View { DesignTextField(title, text: $text, icon: "magnifyingglass") }
}

public struct DesignChip: View {
    public enum Tone: Sendable { case neutral, accent, critical }
    @Environment(\.theme) private var theme
    private let title: String
    private let tone: Tone
    private let isSelected: Bool
    private let count: Int?
    private let onSelect: (() -> Void)?
    private let onRemove: (() -> Void)?
    public init(_ title: String, tone: Tone = .neutral, isSelected: Bool = false, count: Int? = nil,
                onSelect: (() -> Void)? = nil, onRemove: (() -> Void)? = nil) {
        self.title = title; self.tone = tone; self.isSelected = isSelected
        self.count = count; self.onSelect = onSelect; self.onRemove = onRemove
    }
    private var label: some View {
        HStack(spacing: Space.xxs) {
            if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
            Text(title)
            if let count { Text("\(count)").monospacedDigit().fontWeight(.semibold) }
        }.padding(.horizontal, Space.sm).frame(minHeight: onSelect == nil && onRemove == nil ? 28 : Space.minTapTarget)
    }
    public var body: some View {
        HStack(spacing: 0) {
            if let onSelect { Button(action: onSelect) { label }.buttonStyle(.plain) }
            else { label }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").frame(width: Space.minTapTarget, height: Space.minTapTarget)
                }.buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Remove \(title)", comment: "Remove named selection"))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tone == .critical ? theme.critical : (isSelected || tone == .accent ? theme.primary.onPrimarySubtle : theme.secondaryForeground))
        .background(isSelected || tone == .accent ? theme.accentSubtle : theme.inner, in: Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public struct DesignCheckbox: View {
    @Environment(\.theme) private var theme
    private let isOn: Bool
    private let label: String
    private let action: () -> Void
    public init(isOn: Bool, label: String = String(localized: "Selected", comment: "Selection checkbox"),
                action: @escaping () -> Void) {
        self.isOn = isOn; self.label = label; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.badge).fill(isOn ? theme.accent : theme.inner)
                RoundedRectangle(cornerRadius: Radius.badge).stroke(isOn ? theme.accent : theme.border, lineWidth: 1)
                if isOn { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(theme.onAccent) }
            }.frame(width: Space.lg, height: Space.lg)
                .frame(width: Space.minTapTarget, height: Space.minTapTarget).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(isOn ? String(localized: "On", comment: "Checked state") : String(localized: "Off", comment: "Unchecked state"))
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

public struct DesignSegmentedBar<Selection: Hashable>: View {
    @Environment(\.theme) private var theme
    private let items: [(Selection, String)]
    @Binding private var selection: Selection
    public init(items: [(Selection, String)], selection: Binding<Selection>) {
        self.items = items; self._selection = selection
    }
    public var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(items, id: \.0) { item in
                Button { selection = item.0 } label: {
                    Text(item.1).font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: Space.minTapTarget)
                        .background(selection == item.0 ? theme.surface : theme.inner,
                                    in: RoundedRectangle(cornerRadius: Radius.control))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == item.0 ? .isSelected : [])
            }
        }.padding(Space.xxs).background(theme.inner, in: RoundedRectangle(cornerRadius: Radius.control))
    }
}

public struct DesignStateView: View {
    public enum State: Sendable { case empty, loading, error }
    @Environment(\.theme) private var theme
    private let state: State
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    public init(_ state: State, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.state = state; self.title = title; self.message = message; self.actionTitle = actionTitle; self.action = action
    }
    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                if state == .loading { ProgressView() }
                else {
                    Image(systemName: state == .error ? "exclamationmark.arrow.triangle.2.circlepath" : "tray")
                        .font(.title2).foregroundStyle(state == .error ? theme.critical : theme.accent).accessibilityHidden(true)
                }
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(theme.secondaryForeground)
                if let actionTitle, let action { DesignButton(actionTitle, variant: .secondary, action: action) }
            }.padding(.vertical, Space.sm)
        }
    }
}

public struct DesignDockedBar<Content: View>: View {
    private let style: DesignSurfaceStyle
    private let cornerRadius: CGFloat
    private let content: Content
    public init(style: DesignSurfaceStyle = .glass, cornerRadius: CGFloat = Radius.outer,
                @ViewBuilder content: () -> Content) {
        self.style = style; self.cornerRadius = cornerRadius; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) { content }
            .padding(Space.md).frame(maxWidth: .infinity)
            .designSurface(style: style, cornerRadius: cornerRadius)
    }
}

// Each public control is available in both appearances for downstream preview QA.
private struct StrataControlsPreview: View {
    @State private var text = ""
    @State private var selected = 0
    @State private var checked = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                Card(header: { Text("Header") }, content: { Text("Content") },
                     supporting: { Text("Supporting") }, actions: { Text("Actions") })
                DesignButton("Continue", icon: "arrow.right") {}
                DesignButton("Secondary", variant: .secondary) {}
                DesignButton("Ghost", variant: .ghost) {}
                DesignButton("Delete", variant: .destructive) {}
                DesignButton("Loading", isLoading: true) {}
                DesignButton("Disabled", isDisabled: true) {}
                DesignTextField("Name", text: $text)
                DesignSearchField("Search", text: $text)
                DesignChip("Neutral", onSelect: {})
                DesignChip("Selected", tone: .accent, isSelected: true, count: 2, onRemove: {})
                DesignChip("Critical", tone: .critical)
                DesignCheckbox(isOn: checked) { checked.toggle() }
                DesignSegmentedBar(items: [(0, "First"), (1, "Second")], selection: $selected)
                DesignStateView(.empty, title: "Empty", message: "Nothing here yet")
                DesignStateView(.loading, title: "Loading", message: "Please wait")
                DesignStateView(.error, title: "Error", message: "Try again", actionTitle: "Retry", action: {})
                DesignDockedBar { DesignButton("Continue", fullWidth: true) {} }
            }.padding(Space.md)
        }.designTheme()
    }
}

#Preview("Strata controls · Light") {
    StrataControlsPreview().preferredColorScheme(.light)
}
#Preview("Strata controls · Dark") {
    StrataControlsPreview().preferredColorScheme(.dark)
}
