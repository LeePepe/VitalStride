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

    // MARK: - Bottom safe-area content (MY-1446)

    /// Renders the combined bottom layout for the `safeAreaInset(edge: .bottom)`.
    /// Uses a VStack to guarantee the FAB and snackbar never overlap by
    /// construction: FAB is above, snackbar is below.
    ///
    /// MY-1446 P0-1 (no-list-jump): Both undo and rest content are ALWAYS
    /// laid out in a ZStack. Only the active variant has opacity and hit
    /// testing; the inactive variant is invisible but still contributes its
    /// intrinsic height. The ZStack height = max(undo, rest), which is
    /// constant across `.none`, `.undo`, and `.rest` slot transitions. This
    /// guarantees the reserved safe-area inset never changes, preserving the
    /// MY-1421 no-list-jump invariant without any magic-number clearance.
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
            ZStack(alignment: .leading) {
                undoContent()
                    .opacity(snackbarSlot == .undo ? 1 : 0)
                    .allowsHitTesting(snackbarSlot == .undo)
                    .accessibilityHidden(snackbarSlot != .undo)
                restContent()
                    .opacity(snackbarSlot == .rest ? 1 : 0)
                    .allowsHitTesting(snackbarSlot == .rest)
                    .accessibilityHidden(snackbarSlot != .rest)
            }
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

    /// Renders the top snackbar with constant-height envelope. The snackbar
    /// area is ALWAYS laid out (opacity/hit-testing toggled) so the VStack
    /// height does not change when the slot transitions between `.none`,
    /// `.undo`, and `.rest` — preserving the MY-1421 no-list-jump invariant
    /// for the keyboard path.
    ///
    /// Used when the keyboard is visible and the snackbar must render inline
    /// below the compact info band without covering it or causing list jump.
    @ViewBuilder
    @MainActor
    static func topLayout<Snackbar: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder snackbar: () -> Snackbar
    ) -> some View {
        snackbar()
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
            .opacity(snackbarSlot != .none ? 1 : 0)
            .allowsHitTesting(snackbarSlot != .none)
            .accessibilityHidden(snackbarSlot == .none)
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
            // same typography guarantees a stable worst-case height.
            HStack(spacing: Space.gap) {
                Text(String(repeating: "M", count: 40))
                    .font(TypeScale.body)
                    .lineLimit(2)
                Spacer()
                Text("Undo")
                    .font(TypeScale.body.weight(.semibold))
                    .frame(minWidth: Space.minTapTarget, minHeight: Space.minTapTarget)
            }
            .hidden()

            // Active undo content (only when a message is provided)
            if let message {
                HStack(spacing: Space.gap) {
                    Text(message)
                        .font(TypeScale.body)
                        .lineLimit(2)
                        .foregroundStyle(messageColor)
                    Spacer()
                    Button(action: onUndo) {
                        Text(undoTitle)
                            .font(TypeScale.body.weight(.semibold))
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
    /// - Parameter skipTitle: The user-visible localized title for the skip
    ///   button. Required to prevent hardcoded English drift (Quality Bar G).
    @ViewBuilder
    @MainActor
    static func restTimerButtons(
        skipTitle: String,
        neutralBackground: Color = Color.gray.opacity(0.15),
        skipBackground: Color = Color.blue.opacity(0.15),
        minus10AccessibilityLabel: String = "-10s",
        plus10AccessibilityLabel: String = "+10s",
        skipAccessibilityLabel: String = "Skip",
        onMinus10: @escaping () -> Void = {},
        onPlus10: @escaping () -> Void = {},
        onSkip: @escaping () -> Void = {}
    ) -> some View {
        HStack(spacing: 8) {
            restTimerButton(
                title: "-10s",
                background: neutralBackground,
                accessibilityIdentifier: "rest_button_minus10",
                accessibilityLabel: minus10AccessibilityLabel,
                action: onMinus10
            )
            restTimerButton(
                title: "+10s",
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
