import os
import SwiftData
import SwiftUI
import VitalModels

private let logger = Logger(subsystem: "com.vitalstride", category: "CrashRecovery")

/// Presents a recovery alert when orphan workouts are detected at app startup.
///
/// Place this modifier on the root view inside `ContentView`. On first
/// appearance it queries SwiftData for `Workout` records with `endDate == nil`
/// and offers the user three choices for the most recent one — resume,
/// save-and-end, or discard. Any additional orphans are auto-finished
/// immediately so they appear in history rather than lingering as ghosts.
///
/// All user-visible strings are English (matching `Localizable.xcstrings`
/// source language) and route through `String(localized:)` so the alert
/// localizes automatically. Logs record counts and the user's chosen action
/// only — never workout numeric content (privacy constraint).
struct CrashRecoveryModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    /// Passed in explicitly by the caller rather than read from
    /// `@Environment`. The custom modifier is typically applied at the same
    /// level as `.environment(navigation)`, and SwiftUI's environment
    /// values only propagate *down* the view hierarchy — sibling modifiers
    /// in the chain sit outside that writer and would receive a fresh
    /// `AppNavigation`. Taking the dependency by value avoids that gap.
    let navigation: AppNavigation
    /// Injectable persistence hook so tests can simulate `modelContext.save()`
    /// failure without mocking SwiftData. `nil` (the default) uses the real
    /// `modelContext.save()`.
    var saveOverride: (() throws -> Void)?
    @State private var didCheck = false
    @State private var pendingOrphan: Workout?
    @State private var showAlert = false
    @State private var alertSummary: CrashRecoveryService.Summary?
    /// Surfaced when a save/discard operation's `modelContext.save()` throws.
    /// The user gets a retry prompt; the pending workout is kept in
    /// `pendingOrphan` so the original action can be re-attempted.
    @State private var showError = false
    @State private var lastFailedAction: FailedAction?

    /// Which user action triggered a persistence failure. Drives the retry
    /// branch in the error alert.
    enum FailedAction: Equatable {
        case saveAndEnd
        case discard
    }

    func body(content: Content) -> some View {
        content
            .task {
                checkForOrphansIfNeeded()
            }
            .alert(
                String(
                    localized: "Unfinished Workout Detected",
                    comment: "Crash recovery alert title"
                ),
                isPresented: $showAlert,
                presenting: alertSummary
            ) { _ in
                Button(
                    String(
                        localized: "Resume",
                        comment: "Crash recovery resume button"
                    )
                ) {
                    handleResume()
                }
                Button(
                    String(
                        localized: "Save & End",
                        comment: "Crash recovery save-and-end button"
                    )
                ) {
                    handleSaveAndEnd()
                }
                Button(
                    String(
                        localized: "Discard",
                        comment: "Crash recovery discard button"
                    ),
                    role: .destructive
                ) {
                    handleDiscard()
                }
            } message: { summary in
                Text(messageText(for: summary))
            }
            .alert(
                String(
                    localized: "Couldn't Save Workout",
                    comment: "Crash recovery save-failure alert title"
                ),
                isPresented: $showError,
                presenting: lastFailedAction
            ) { action in
                Button(
                    String(
                        localized: "Retry",
                        comment: "Crash recovery retry failed save button"
                    )
                ) {
                    retry(action)
                }
                Button(
                    String(
                        localized: "Cancel",
                        comment: "Crash recovery cancel failed save button"
                    ),
                    role: .cancel
                ) {
                    // Re-open the original choice alert so the user can pick
                    // a different action rather than being left with an
                    // unfinished workout silently in the background.
                    lastFailedAction = nil
                    showAlert = pendingOrphan != nil
                }
            } message: { _ in
                Text(
                    String(
                        localized: "Saving failed. You can retry, or cancel and try a different option.",
                        comment: "Crash recovery save-failure alert body"
                    )
                )
            }
    }

    // MARK: - Detection

    private func checkForOrphansIfNeeded() {
        guard !didCheck else { return }
        didCheck = true

        let orphans = CrashRecoveryService.findOrphans(in: modelContext)
        logger.info("Crash recovery check: unfinishedCount=\(orphans.count, privacy: .public)")
        guard !orphans.isEmpty else { return }

        let partition = CrashRecoveryService.partition(orphans)

        if !partition.autoFinish.isEmpty {
            CrashRecoveryService.autoFinishOrphans(partition.autoFinish)
            let saved = persist(reason: "auto_finish_extras")
            if saved {
                logger.info(
                    "Auto-finished orphan workouts: count=\(partition.autoFinish.count, privacy: .public)"
                )
            }
            // If auto-finish save failed we still continue to show the
            // resume alert for the most recent orphan — the user-facing
            // outcome of save_and_end / discard will be re-attempted on
            // their choice below.
        }

        if let resumable = partition.resumable {
            pendingOrphan = resumable
            alertSummary = CrashRecoveryService.summary(for: resumable)
            showAlert = true
        }
    }

    // MARK: - Actions

    private func handleResume() {
        guard let workout = pendingOrphan else { return }
        logger.info("Crash recovery action: choice=resume")
        navigation.crashRecoveryResume = workout
        navigation.selectedTab = .workout
        clearAlertState()
    }

    private func handleSaveAndEnd() {
        guard let workout = pendingOrphan else { return }
        logger.info("Crash recovery action: choice=save")
        let outcome = CrashRecoveryService.saveAndEnd(
            workout: workout,
            context: modelContext,
            save: saveOverride
        )
        finish(action: .saveAndEnd, outcome: outcome)
    }

    private func handleDiscard() {
        guard let workout = pendingOrphan else { return }
        logger.info("Crash recovery action: choice=discard")
        let outcome = CrashRecoveryService.discard(
            workout: workout,
            context: modelContext,
            save: saveOverride
        )
        finish(action: .discard, outcome: outcome)
    }

    private func finish(
        action: FailedAction,
        outcome: CrashRecoveryService.ResolutionOutcome
    ) {
        switch outcome {
        case .success:
            clearAlertState()
        case .persistFailed:
            logger.error(
                "Crash recovery save failed: action=\(String(describing: action), privacy: .public)"
            )
            surfaceFailure(action)
        }
    }

    private func retry(_ action: FailedAction) {
        logger.info(
            "Crash recovery retry: action=\(String(describing: action), privacy: .public)"
        )
        lastFailedAction = nil
        switch action {
        case .saveAndEnd:
            handleSaveAndEnd()
        case .discard:
            handleDiscard()
        }
    }

    private func surfaceFailure(_ action: FailedAction) {
        lastFailedAction = action
        // Keep `pendingOrphan` and `alertSummary` populated so the retry
        // path knows which workout to operate on. The choice alert is
        // dismissed while the error alert is shown; the cancel branch
        // re-opens it.
        showAlert = false
        showError = true
    }

    private func clearAlertState() {
        pendingOrphan = nil
        alertSummary = nil
        lastFailedAction = nil
    }

    // MARK: - Helpers

    private func persist(reason: String) -> Bool {
        do {
            if let saveOverride {
                try saveOverride()
            } else {
                try modelContext.save()
            }
            return true
        } catch {
            logger.error(
                // swiftlint:disable:next line_length
                "Crash recovery save failed: reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private func messageText(for summary: CrashRecoveryService.Summary) -> String {
        let startedAt = summary.startDate.formatted(
            date: .abbreviated,
            time: .shortened
        )

        if summary.isEmpty {
            return String(
                localized: "Started at \(startedAt). Empty workout (no exercises) — recommend discarding.",
                comment: "Crash recovery message for empty workout"
            )
        }
        return String(
            localized: "Started at \(startedAt). Recorded \(summary.exerciseCount) exercises across \(summary.setCount) sets.",
            comment: "Crash recovery message including exercise and set counts"
        )
    }
}

extension View {
    /// Attaches the crash recovery detection + alert to a view.
    ///
    /// - Parameter navigation: The shared navigation observable. Pass the
    ///   same instance you supply to `.environment(navigation)` so that the
    ///   "Resume" choice can route through `crashRecoveryResume` /
    ///   `selectedTab`.
    func detectsCrashRecovery(navigation: AppNavigation) -> some View {
        modifier(CrashRecoveryModifier(navigation: navigation))
    }
}
