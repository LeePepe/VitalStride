import Foundation

@MainActor
@Observable
final class RestTimerController {
    private(set) var restEndDate: Date?

    func startRest(duration: TimeInterval = 90) {
        restEndDate = Date().addingTimeInterval(duration)
    }

    func skipRest() {
        restEndDate = nil
    }

    func handleTimerTask() async {
        guard let restEnd = restEndDate else { return }
        let remaining = restEnd.timeIntervalSinceNow
        guard remaining > 0 else {
            if restEndDate == restEnd {
                restEndDate = nil
            }
            return
        }
        do {
            try await Task.sleep(for: .seconds(remaining))
            if restEndDate == restEnd {
                restEndDate = nil
            }
        } catch {}
    }
}
