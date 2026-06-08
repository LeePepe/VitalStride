import Foundation

enum RestPhase {
    case idle
    case resting
    case completed
}

@MainActor
@Observable
final class RestTimerController {
    private(set) var restEndDate: Date?
    private(set) var restTotalDuration: TimeInterval?
    private(set) var phase: RestPhase = .idle

    let completedDisplayDuration: TimeInterval

    init(completedDisplayDuration: TimeInterval = 2) {
        self.completedDisplayDuration = completedDisplayDuration
    }

    func startRest(duration: TimeInterval = 90) {
        restEndDate = Date().addingTimeInterval(duration)
        restTotalDuration = duration
        phase = .resting
    }

    func adjustRest(by seconds: TimeInterval) {
        guard phase == .resting, let currentEnd = restEndDate else { return }
        restEndDate = currentEnd.addingTimeInterval(seconds)
        restTotalDuration = max(0, (restTotalDuration ?? 0) + seconds)
    }

    func skipRest() {
        restEndDate = nil
        restTotalDuration = nil
        phase = .idle
    }

    func dismissCompleted() {
        guard phase == .completed else { return }
        restEndDate = nil
        restTotalDuration = nil
        phase = .idle
    }

    func handleTimerTask() async {
        guard let restEnd = restEndDate, phase == .resting else { return }
        let remaining = restEnd.timeIntervalSinceNow
        if remaining > 0 {
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch { return }
        }
        guard restEndDate == restEnd else { return }
        phase = .completed
        do {
            try await Task.sleep(for: .seconds(completedDisplayDuration))
        } catch { return }
        guard restEndDate == restEnd, phase == .completed else { return }
        restEndDate = nil
        restTotalDuration = nil
        phase = .idle
    }
}
