// swiftlint:disable no_hardcoded_chinese
// MY-1269 / MY-1282: Chinese string values are xcstrings source keys resolved
// via String(localized:). Rule silenced at file scope pending ASCII-key migration.
import DesignKit
import HealthKit
import HealthKitService
import SwiftUI
import os

// MARK: - Watch → Phone sender factory
//
// Production wiring for the in-workout screen's primary-action side
// effect (MY-1292 P0-1). The display view-model needs a
// `WatchSetCompletedSending` seam so complete/log/finish taps deliver
// a `SetCompletedEvent` to the paired iPhone. On watchOS we hand it a
// real `DefaultWatchToPhoneSender` (thin wrapper over the shared
// `WCSession.default`) via the `toPhoneSender:` convenience init on
// `WatchWorkoutViewModel`. On preview/other platforms we fall back to
// `NoopWatchToPhoneSender` so previews still compile.
//
// Privacy §I: neither branch logs the event body; `DefaultWatchToPhoneSender`
// only logs the message `kind` + transport, and `NoopWatchToPhoneSender`
// throws without logging.
private enum WatchDisplaySenderFactory {
    @MainActor
    static func makeViewModel(
        manager: any WorkoutSessionManaging
    ) -> WatchWorkoutViewModel {
        #if os(watchOS) && canImport(WatchConnectivity)
        return WatchWorkoutViewModel(
            manager: manager,
            toPhoneSender: DefaultWatchToPhoneSender()
        )
        #else
        return WatchWorkoutViewModel(
            manager: manager,
            toPhoneSender: NoopWatchToPhoneSender()
        )
        #endif
    }
}

// MARK: - WatchWorkoutLifecycleViewModel
//
// Owns the watch-side workout lifecycle for the strength-training screen
// (MY-1282). Responsibilities:
//   * Request HealthKit authorization on-device (watchOS-side share/read set).
//   * Drive `WorkoutSessionManager.startSession()` / `endSession(save:)`.
//   * Track a coarse UI state — idle / requestingAuth / active / ending /
//     failed(reason) — so the view can render start/end/failure states.
//
// Renamed from `WatchWorkoutViewModel` in MY-1290 so the new display-state
// adapter (`WatchWorkoutViewModel` in `WatchWorkoutViewModel.swift`) can
// take the shorter name without collision. This lifecycle VM is invoked
// by the entry screen; the display-state VM is owned by the in-workout
// screen (MY-1291/MY-1292) once composition lands.
//
// Privacy §I: NEVER log HR values. This view-model does not hold HR values
// (they flow watch → iPhone through `WatchToPhoneSending` inside the manager);
// the on-watch UI in scope for T002 is start/end only.
//
// Concurrency §II: `@MainActor` isolation for UI-driving state; manager
// callbacks are already async and delivered onto the caller's actor.
@MainActor
final class WatchWorkoutLifecycleViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingAuthorization
        case starting
        case active
        case ending
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let service: HealthKitService
    let manager: any WorkoutSessionManaging
    private let logger = Logger(subsystem: "com.vitalstride", category: "WatchWorkoutVM")

    init(deviceIdentifier: String = WatchWorkoutLifecycleViewModel.defaultDeviceIdentifier) {
        let service = HealthKitService(deviceIdentifier: deviceIdentifier)
        self.service = service
        self.manager = service.makeWorkoutSessionManager()
    }

    /// Test / preview seam — inject a stubbed manager without touching HealthKit.
    init(manager: any WorkoutSessionManaging, initialState: State = .idle) {
        self.service = HealthKitService(deviceIdentifier: "preview-device")
        self.manager = manager
        self.state = initialState
    }

    static var defaultDeviceIdentifier: String {
        #if os(watchOS)
        return "watchOS-\(ProcessInfo.processInfo.hostName)"
        #else
        return "watchOS"
        #endif
    }

    func startWorkoutTapped() {
        guard state == .idle || isFailed(state) else { return }
        state = .requestingAuthorization
        Task { [weak self] in
            guard let self else { return }
            do {
                // Ask HealthKit for the write-workout + read set. On watchOS
                // this pops the standard system authorization sheet the
                // first time.
                try await service.requestAuthorization()
            } catch {
                logger.error("watch_auth_request_failed error=\(error.localizedDescription, privacy: .private)")
                await MainActor.run {
                    self.state = .failed(
                        String(localized: "HealthKit 授权失败", comment: "Watch workout: auth failure")
                    )
                }
                return
            }
            await MainActor.run { self.state = .starting }
            do {
                try await manager.startSession()
                await MainActor.run { self.state = .active }
            } catch {
                logger.error("watch_workout_start_failed error=\(error.localizedDescription, privacy: .private)")
                await MainActor.run {
                    self.state = .failed(
                        String(localized: "启动失败", comment: "Watch workout: session start failed")
                    )
                }
            }
        }
    }

    func endWorkoutTapped(save: Bool = true) {
        guard state == .active else { return }
        state = .ending
        Task { [weak self] in
            guard let self else { return }
            _ = await manager.endSession(save: save)
            await MainActor.run { self.state = .idle }
        }
    }

    private func isFailed(_ state: State) -> Bool {
        if case .failed = state { return true }
        return false
    }

    var failureReason: String? {
        if case .failed(let reason) = state { return reason }
        return nil
    }
}

// MARK: - WatchContentView

struct WatchContentView: View {
    @Environment(\.theme) private var theme
    @StateObject private var viewModel = WatchWorkoutLifecycleViewModel()

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    StrengthWorkoutView(viewModel: viewModel)
                } label: {
                    Label(String(localized: "开始训练", comment: ""), systemImage: "dumbbell.fill")
                        .tint(theme.primary.primary)
                }
                .accessibilityLabel(String(localized: "开始训练", comment: "Start workout a11y (watch)"))
            }
            .navigationTitle("VitalStride")
        }
    }
}

// MARK: - StrengthWorkoutView

/// Watch-side start / active / end UI for the strength-training session
/// (ADR-0010 narrow scope). When the session is `.active` this view
/// hands off to `WatchInWorkoutView` (MY-1292) which renders the
/// configured preset from the merged display state; the pre-active
/// states (idle / auth / start / end / failed) still render the coarse
/// lifecycle chrome so users see progress before the WC pipeline is up.
struct StrengthWorkoutView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var viewModel: WatchWorkoutLifecycleViewModel

    /// Display-state adapter (MY-1290) fed by the merged WC streams. It
    /// shares the lifecycle VM's underlying `WorkoutSessionManaging` so
    /// state / config / HR / connection events all funnel from one
    /// source of truth. The `WatchSetCompletedSending` seam is supplied
    /// by `WatchDisplaySenderFactory`, which wires the real
    /// `DefaultWatchToPhoneSender` on watchOS (MY-1292 P0-1).
    @StateObject private var displayModel: WatchWorkoutViewModel

    init(viewModel: WatchWorkoutLifecycleViewModel) {
        self.viewModel = viewModel
        self._displayModel = StateObject(
            wrappedValue: WatchDisplaySenderFactory.makeViewModel(
                manager: viewModel.manager
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.state == .active {
                WatchInWorkoutView(viewModel: displayModel)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .destructive) {
                                viewModel.endWorkoutTapped(save: true)
                            } label: {
                                Image(systemName: "stop.fill")
                                    .accessibilityLabel(
                                        String(localized: "结束训练", comment: "Watch: end workout toolbar")
                                    )
                            }
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    headerView
                    controlView
                }
                .padding()
                .navigationTitle(String(localized: "力量训练", comment: "Watch strength workout title"))
            }
        }
        .onChange(of: viewModel.state) { _, new in
            switch new {
            case .active:
                displayModel.start()
            case .idle, .ending:
                displayModel.stop()
            case .failed, .requestingAuthorization, .starting:
                break
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        switch viewModel.state {
        case .idle:
            Text(String(localized: "准备开始", comment: "Watch workout: idle prompt"))
                .font(.headline)
                .foregroundStyle(theme.neutrals.text2)
        case .requestingAuthorization:
            ProgressView()
            Text(String(localized: "请求 HealthKit 权限…", comment: "Watch workout: requesting auth"))
                .font(.footnote)
                .foregroundStyle(theme.neutrals.text2)
        case .starting:
            ProgressView()
            Text(String(localized: "启动中…", comment: "Watch workout: starting"))
                .font(.footnote)
                .foregroundStyle(theme.neutrals.text2)
        case .active:
            Text(String(localized: "训练中", comment: "Watch workout: active"))
                .font(.headline)
                .foregroundStyle(theme.primary.primary)
        case .ending:
            ProgressView()
            Text(String(localized: "正在结束…", comment: "Watch workout: ending"))
                .font(.footnote)
                .foregroundStyle(theme.neutrals.text2)
        case .failed:
            Text(viewModel.failureReason ?? String(localized: "启动失败", comment: "Watch workout: failed"))
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var controlView: some View {
        switch viewModel.state {
        case .idle, .failed:
            Button {
                viewModel.startWorkoutTapped()
            } label: {
                Label(String(localized: "开始训练", comment: "Watch workout: start button"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(String(localized: "开始训练", comment: "Watch workout: start button a11y"))

        case .active:
            Button(role: .destructive) {
                viewModel.endWorkoutTapped(save: true)
            } label: {
                Label(String(localized: "结束训练", comment: "Watch workout: end button"), systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(String(localized: "结束训练", comment: "Watch workout: end button a11y"))

        case .requestingAuthorization, .starting, .ending:
            EmptyView()
        }
    }
}

#Preview("WatchContentView — idle") {
    WatchContentView()
        .designThemePreview()
}

// A second representative preview so reviewers can eyeball the active +
// failed states without running the workout end-to-end. Uses the
// `NoopWorkoutSessionManager` seam so no HealthKit call is made.
#Preview("StrengthWorkoutView — active") {
    NavigationStack {
        StrengthWorkoutView(
            viewModel: WatchWorkoutLifecycleViewModel(
                manager: NoopWorkoutSessionManager(),
                initialState: .active
            )
        )
    }
    .designThemePreview()
}

#Preview("StrengthWorkoutView — failed") {
    NavigationStack {
        StrengthWorkoutView(
            viewModel: WatchWorkoutLifecycleViewModel(
                manager: NoopWorkoutSessionManager(),
                initialState: .failed(String(localized: "启动失败", comment: "preview failure"))
            )
        )
    }
    .designThemePreview()
}
