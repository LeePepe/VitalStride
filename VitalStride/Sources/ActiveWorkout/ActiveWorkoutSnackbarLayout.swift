import DesignKit
import SwiftUI

// MARK: - ActiveWorkoutSnackbarLayout (MY-1421, MY-1446)

/// Pure layout-decision logic for the snackbar, extracted so tests can
/// verify contracts without spinning up the full `ActiveWorkoutView`.
///
/// MY-1446: extended to provide safe-area-driven rendering that guarantees
/// non-overlap between snackbar, FAB, and info band by construction (VStack).
enum ActiveWorkoutSnackbarLayout {
    /// Determines which edge the snackbar should render at based on keyboard
    /// visibility. When the custom numeric keyboard is on screen, the snackbar
    /// moves to the top edge so it remains fully visible and never overlaps
    /// the keyboard.
    static func resolveEdge(isKeyboardVisible: Bool) -> VerticalEdge {
        isKeyboardVisible ? .top : .bottom
    }

    @MainActor
    static func activeSlotContent<UndoContent: View, RestContent: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder undoContent: () -> UndoContent,
        @ViewBuilder restContent: () -> RestContent
    ) -> some View {
        switch snackbarSlot {
        case .undo:
            undoContent()
        case .rest:
            restContent()
        case .none:
            EmptyView()
        }
    }

    static func activeContentKey(_ snackbarSlot: BottomSnackbarSlot) -> String? {
        switch snackbarSlot {
        case .none:
            nil
        case .rest:
            "rest"
        case .undo:
            "undo"
        }
    }

    // MARK: - Shared slot envelope (MY-1446)

    /// Shared constant-height envelope used by both bottom and top snackbar
    /// layouts. Both undo and rest content are ALWAYS laid out in a ZStack.
    /// Only the active variant has opacity and hit testing; the inactive variant
    /// is invisible but still contributes its intrinsic height. The ZStack
    /// height = max(undo, rest), constant across `.none`/`.undo`/`.rest`
    /// transitions — preserving the MY-1421 no-list-jump invariant.
    @ViewBuilder
    @MainActor
    static func slotEnvelope<UndoContent: View, RestContent: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder undoContent: () -> UndoContent,
        @ViewBuilder restContent: () -> RestContent
    ) -> some View {
        // Both branches are always laid out for constant-height contract.
        // Only the active branch has opacity/hit-testing.
        ZStack(alignment: .leading) {
            undoContent()
                .opacity(snackbarSlot == .undo ? 1 : 0)
                .allowsHitTesting(snackbarSlot == .undo)
            restContent()
                .opacity(snackbarSlot == .rest ? 1 : 0)
                .allowsHitTesting(snackbarSlot == .rest)
        }
        // On iOS 26, `.accessibilityHidden(true)` on an inactive branch does
        // not suppress its SwiftUI descendants from the accessibility tree.
        // `.accessibilityRepresentation` completely replaces the ZStack's
        // accessibility subtree with only the active content, so inactive
        // labels/buttons are never exposed to VoiceOver or XCUI queries.
        .accessibilityRepresentation {
            activeSlotContent(
                snackbarSlot: snackbarSlot,
                undoContent: undoContent,
                restContent: restContent
            )
        }
    }

    // MARK: - Bottom safe-area content (MY-1446)

    /// Renders the combined bottom layout for the `safeAreaInset(edge: .bottom)`.
    /// Uses a VStack to guarantee the FAB and snackbar never overlap by
    /// construction: FAB is above, snackbar is below.
    ///
    /// MY-1446 P0-1 (no-list-jump): delegates to `slotEnvelope` for the
    /// constant-height ZStack contract.
    @ViewBuilder
    @MainActor
    static func bottomSafeAreaContent<UndoContent: View, RestContent: View, FAB: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder undoContent: () -> UndoContent,
        @ViewBuilder restContent: () -> RestContent,
        @ViewBuilder fab: () -> FAB
    ) -> some View {
        VStack(spacing: 0) {
            fab()
            slotEnvelope(snackbarSlot: snackbarSlot, undoContent: undoContent, restContent: restContent)
                .padding(.horizontal, Space.cardPadding)
                .padding(.vertical, Space.gap)
                .frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading)
                .background(snackbarSlot != .none ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(
                    color: snackbarSlot != .none ? .black.opacity(0.15) : .clear,
                    radius: 8, y: 4
                )
                .padding(.horizontal, Space.cardPadding)
                .padding(.bottom, Space.cardPadding)
        }
    }

    // MARK: - Top layout (MY-1446)

    /// Renders the top snackbar with constant-height envelope. Delegates to
    /// `slotEnvelope` so undo/rest height is constant across slot transitions.
    ///
    /// Used when the keyboard is visible and the snackbar must render inline
    /// below the compact info band without covering it or causing list jump.
    @ViewBuilder
    @MainActor
    static func topLayout<UndoContent: View, RestContent: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder undoContent: () -> UndoContent,
        @ViewBuilder restContent: () -> RestContent
    ) -> some View {
        slotEnvelope(snackbarSlot: snackbarSlot, undoContent: undoContent, restContent: restContent)
            .padding(.horizontal, Space.cardPadding)
            .padding(.vertical, Space.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(snackbarSlot != .none ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(
                color: snackbarSlot != .none ? .black.opacity(0.15) : .clear,
                radius: 8, y: -4
            )
            .padding(.horizontal, Space.cardPadding)
            .padding(.top, Space.inline)
    }

    // MARK: - Top composition (MY-1446, testable)

    /// Renders the production keyboard-visible composition: info band content
    /// above the top snackbar, in a VStack. This is the same structure that
    /// `ActiveWorkoutView.body` uses when `isKeyboardVisible == true`.
    ///
    /// Extracted so tests exercise the actual production composition path
    /// (not a test-local mirror), proving the snackbar cannot overlap the
    /// info band by VStack construction.
    @ViewBuilder
    @MainActor
    static func topComposition<InfoBand: View, UndoContent: View, RestContent: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder infoBand: () -> InfoBand,
        @ViewBuilder undoContent: () -> UndoContent,
        @ViewBuilder restContent: () -> RestContent
    ) -> some View {
        VStack(spacing: 0) {
            infoBand()
            topLayout(
                snackbarSlot: snackbarSlot,
                undoContent: undoContent,
                restContent: restContent
            )
        }
    }


    // MARK: - Undo envelope (MY-1446, testable)

    /// Renders the undo snackbar envelope with a ZStack-based stable-height
    /// contract. A hidden sizing reference (two-line text + button) is always
    /// laid out, guaranteeing the envelope height is message-independent.
    /// The real message text uses `.lineLimit(2)` matching the reference so
    /// it can never exceed the reference height at any Dynamic Type size.
    ///
    /// Production `ActiveWorkoutView.undoSnackbarEnvelope` delegates here so
    /// tests exercise the actual delivered code path.
    /// The Dynamic Type-participating font used for undo message and action text.
    /// Uses `.subheadline` text style (scales with system settings) while the
    /// stable-height contract is preserved by the hidden two-line sizing reference
    /// using the same font.
    static let undoFont: Font = .subheadline

    @ViewBuilder
    @MainActor
    static func undoEnvelope(
        message: String?,
        undoTitle: String = "Undo",
        messageColor: Color = .primary,
        undoColor: Color = .blue,
        undoAccessibilityLabel: String = "Undo deletion",
        onUndo: @escaping () -> Void = {}
    ) -> some View {
        ZStack(alignment: .leading) {
            // Hidden sizing reference: two-line body text + button at the
            // same Dynamic Type-participating typography guarantees a stable
            // worst-case height that scales with accessibility content sizes.
            HStack(spacing: Space.gap) {
                Text(String(repeating: "M", count: 40))
                    .font(undoFont)
                    .lineLimit(2)
                Spacer()
                Text("Undo")
                    .font(undoFont.weight(.semibold))
                    .frame(minWidth: Space.minTapTarget, minHeight: Space.minTapTarget)
            }
            .hidden()

            // Active undo content (only when a message is provided)
            if let message {
                HStack(spacing: Space.gap) {
                    Text(message)
                        .font(undoFont)
                        .lineLimit(2)
                        .foregroundStyle(messageColor)
                    Spacer()
                    Button(action: onUndo) {
                        Text(undoTitle)
                            .font(undoFont.weight(.semibold))
                            .foregroundStyle(undoColor)
                            .frame(minWidth: Space.minTapTarget, minHeight: Space.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(undoAccessibilityLabel)
                }
            }
        }
    }

    // MARK: - Rest envelope (MY-1446, testable)

    /// Renders the rest snackbar envelope with a ZStack-based stable-height
    /// contract. A hidden sizing reference (progress circle + buttons) is
    /// always laid out, guaranteeing the envelope height matches the tallest
    /// variant regardless of whether "completed" or "resting" is displayed.
    ///
    /// Production `ActiveWorkoutView.restSnackbarEnvelope` delegates here so
    /// tests exercise the actual delivered code path.
    @ViewBuilder
    @MainActor
    static func restEnvelope<Content: View>(
        skipTitle: String,
        neutralBackground: Color = Color.gray.opacity(0.15),
        skipBackground: Color = Color.blue.opacity(0.15),
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            // Hidden sizing reference: always present, guarantees the envelope
            // height matches the tallest rest variant (progress circle + buttons).
            HStack {
                Circle()
                    .stroke(Color.clear, lineWidth: 3)
                    .frame(width: 32, height: 32)
                Spacer()
                restTimerButtons(
                    skipTitle: skipTitle,
                    neutralBackground: neutralBackground,
                    skipBackground: skipBackground
                )
            }
            .hidden()

            // Active rest content
            content()
        }
    }

    // MARK: - Rest timer button layout (MY-1446, testable)

    /// A single rest timer button with production sizing constraints.
    /// Extracted so tests can measure individual buttons without relying on
    /// SwiftUI→UIView identifier propagation.
    @ViewBuilder
    @MainActor
    static func restTimerButton(
        title: String,
        isBold: Bool = false,
        background: Color = Color.gray.opacity(0.15),
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(title, action: action)
            .font(.caption)
            .fontWeight(isBold ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Capsule())
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(accessibilityLabel)
    }

    /// Renders the rest timer adjust buttons (-10s, +10s, Skip) with the
    /// production layout (including `.frame(minWidth: 44, minHeight: 44)` and
    /// accessibility identifiers). Extracted as a static helper so tests can
    /// verify hit targets on the actual production layout. Production calls
    /// this with themed colors and real actions.
    ///
    /// - Parameters:
    ///   - minus10Title: Localized visible title for the -10s button.
    ///   - plus10Title: Localized visible title for the +10s button.
    ///   - skipTitle: Localized visible title for the skip button.
    @ViewBuilder
    @MainActor
    static func restTimerButtons(
        minus10Title: String = String(localized: "rest_timer.minus10.title", defaultValue: "-10s", comment: "Rest timer subtract 10 seconds button title"),
        plus10Title: String = String(localized: "rest_timer.plus10.title", defaultValue: "+10s", comment: "Rest timer add 10 seconds button title"),
        skipTitle: String,
        neutralBackground: Color = Color.gray.opacity(0.15),
        skipBackground: Color = Color.blue.opacity(0.15),
        minus10AccessibilityLabel: String = String(localized: "rest_timer.minus10.a11y", defaultValue: "Subtract 10 seconds", comment: "Rest timer -10s accessibility label"),
        plus10AccessibilityLabel: String = String(localized: "rest_timer.plus10.a11y", defaultValue: "Add 10 seconds", comment: "Rest timer +10s accessibility label"),
        skipAccessibilityLabel: String = String(localized: "rest_timer.skip.a11y", defaultValue: "Skip rest", comment: "Rest timer skip accessibility label"),
        onMinus10: @escaping () -> Void = {},
        onPlus10: @escaping () -> Void = {},
        onSkip: @escaping () -> Void = {}
    ) -> some View {
        HStack(spacing: 8) {
            restTimerButton(
                title: minus10Title,
                background: neutralBackground,
                accessibilityIdentifier: "rest_button_minus10",
                accessibilityLabel: minus10AccessibilityLabel,
                action: onMinus10
            )
            restTimerButton(
                title: plus10Title,
                background: neutralBackground,
                accessibilityIdentifier: "rest_button_plus10",
                accessibilityLabel: plus10AccessibilityLabel,
                action: onPlus10
            )
            restTimerButton(
                title: skipTitle,
                isBold: true,
                background: skipBackground,
                accessibilityIdentifier: "rest_button_skip",
                accessibilityLabel: skipAccessibilityLabel,
                action: onSkip
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SnackbarFocusRouter (MY-1446, testable)

/// Pure-logic focus router for snackbar VoiceOver focus management.
/// Extracted from `ActiveWorkoutView`'s `.onChange` closures so tests can
/// verify focus-routing sequences without spinning up a full SwiftUI view.
///
/// Rules:
/// - `.none` → clear both bottom and top focus
/// - Active slot (`.undo`/`.rest`) + keyboard visible → top focus only
/// - Active slot + keyboard hidden → bottom focus only
/// - Keyboard visibility change with active slot → migrate focus
struct SnackbarFocusRouter {
    /// Focus state pair: (bottomFocused, topFocused)
    struct FocusState: Equatable {
        var bottomFocused: Bool
        var topFocused: Bool

        static let cleared = FocusState(bottomFocused: false, topFocused: false)
    }

    /// Resolves focus state when the snackbar slot changes.
    static func resolveSlotChange(
        newSlot: BottomSnackbarSlot,
        isKeyboardVisible: Bool
    ) -> FocusState {
        switch newSlot {
        case .none:
            return .cleared
        case .undo, .rest:
            if isKeyboardVisible {
                return FocusState(bottomFocused: false, topFocused: true)
            } else {
                return FocusState(bottomFocused: true, topFocused: false)
            }
        }
    }

    /// Resolves focus state when keyboard visibility changes while a snackbar
    /// is active. Returns `nil` if slot is `.none` (no migration needed).
    static func resolveKeyboardChange(
        keyboardNowVisible: Bool,
        currentSlot: BottomSnackbarSlot
    ) -> FocusState? {
        guard currentSlot != .none else { return nil }
        if keyboardNowVisible {
            return FocusState(bottomFocused: false, topFocused: true)
        } else {
            return FocusState(bottomFocused: true, topFocused: false)
        }
    }
}

// MARK: - ActiveWorkoutFABContainer (MY-1421)

/// Testable wrapper that isolates the FAB's safeAreaInset-contributing layout
/// from the rest of `ActiveWorkoutView`. The key invariant: the container's
/// intrinsic height is **constant** regardless of snackbar state.
///
/// MY-1446: the offset hack is removed. The FAB's position is now constant
/// because the snackbar occupies its own distinct region below the FAB
/// (via the unified `bottomSafeAreaContent` VStack). The `snackbarSlot`
/// parameter is preserved for API stability and test compatibility.
enum ActiveWorkoutFABContainer {
    /// Snackbar clearance constant — retained for backward compatibility with
    /// existing tests and any code that references it.
    static let snackbarClearance: CGFloat =
        Space.cardPadding + Space.gap + Space.minTapTarget + Space.gap + Space.cardPadding

    /// The FAB layout body. Intrinsic height is constant regardless of
    /// snackbar state (the `snackbarSlot` parameter no longer affects layout).
    @ViewBuilder
    @MainActor
    static func body<Content: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
    }
}
