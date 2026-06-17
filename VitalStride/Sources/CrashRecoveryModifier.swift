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
/// All user-visible strings flow through `LocalizedStringKey` / `String(localized:)`
/// so the alert localizes automatically. Logs record counts and the user's
/// chosen action only — never workout numeric content (privacy constraint).
struct CrashRecoveryModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    /// Passed in explicitly by the caller rather than read from
    /// `@Environment`. The custom modifier is typically applied at the same
    /// level as `.environment(navigation)`, and SwiftUI's environment
    /// values only propagate *down* the view hierarchy — sibling modifiers
    /// in the chain sit outside that writer and would receive a fresh
    /// `AppNavigation`. Taking the dependency by value avoids that gap.
    let navigation: AppNavigation
    @State private var didCheck = false
    @State private var pendingOrphan: Workout?
    @State private var showAlert = false
    @State private var alertSummary: CrashRecoveryService.Summary?

    func body(content: Content) -> some View {
        content
            .task {
                checkForOrphansIfNeeded()
            }
            .alert(
                String(
                    localized: "检测到未完成的训练",
                    comment: "Crash recovery alert title"
                ),
                isPresented: $showAlert,
                presenting: alertSummary
            ) { _ in
                Button(
                    String(
                        localized: "恢复训练",
                        comment: "Crash recovery resume button"
                    )
                ) {
                    handleResume()
                }
                Button(
                    String(
                        localized: "保存并结束",
                        comment: "Crash recovery save-and-end button"
                    )
                ) {
                    handleSaveAndEnd()
                }
                Button(
                    String(
                        localized: "丢弃",
                        comment: "Crash recovery discard button"
                    ),
                    role: .destructive
                ) {
                    handleDiscard()
                }
            } message: { summary in
                Text(messageText(for: summary))
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
        workout.finish(at: Date())
        _ = persist(reason: "save_and_end")
        clearAlertState()
    }

    private func handleDiscard() {
        guard let workout = pendingOrphan else { return }
        logger.info("Crash recovery action: choice=discard")
        modelContext.delete(workout)
        _ = persist(reason: "discard")
        clearAlertState()
    }

    private func clearAlertState() {
        pendingOrphan = nil
        alertSummary = nil
    }

    // MARK: - Helpers

    private func persist(reason: String) -> Bool {
        do {
            try modelContext.save()
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
                localized: "训练开始于 \(startedAt)，空训练（未添加动作），建议丢弃。",
                comment: "Crash recovery message for empty workout"
            )
        }
        return String(
            localized: "训练开始于 \(startedAt)，已记录 \(summary.exerciseCount) 个动作、\(summary.setCount) 组数据。",
            comment: "Crash recovery message including exercise and set counts"
        )
    }
}

extension View {
    /// Attaches the crash recovery detection + alert to a view.
    ///
    /// - Parameter navigation: The shared navigation observable. Pass the
    ///   same instance you supply to `.environment(navigation)` so that the
    ///   "恢复训练" choice can route through `crashRecoveryResume` /
    ///   `selectedTab`.
    func detectsCrashRecovery(navigation: AppNavigation) -> some View {
        modifier(CrashRecoveryModifier(navigation: navigation))
    }
}
