import Foundation

@MainActor
@Observable
final class RestTimerController {
    private(set) var restEndDate: Date?
    private(set) var restTotalDuration: TimeInterval?

    func startRest(duration: TimeInterval = 90) {
        restEndDate = Date().addingTimeInterval(duration)
        restTotalDuration = duration
    }

    func adjustRest(by seconds: TimeInterval) {
        guard let currentEnd = restEndDate else { return }
        let newEnd = currentEnd.addingTimeInterval(seconds)
        if newEnd.timeIntervalSinceNow <= 0 {
            restEndDate = nil
            restTotalDuration = nil
        } else {
            restEndDate = newEnd
            restTotalDuration = max(0, (restTotalDuration ?? 0) + seconds)
        }
    }

    func skipRest() {
        restEndDate = nil
        restTotalDuration = nil
    }

    func handleTimerTask() async {
        guard let restEnd = restEndDate else { return }
        let remaining = restEnd.timeIntervalSinceNow
        guard remaining > 0 else {
            if restEndDate == restEnd {
                restEndDate = nil
                restTotalDuration = nil
            }
            return
        }
        do {
            try await Task.sleep(for: .seconds(remaining))
            if restEndDate == restEnd {
                restEndDate = nil
                restTotalDuration = nil
            }
        } catch {}
    }
}
