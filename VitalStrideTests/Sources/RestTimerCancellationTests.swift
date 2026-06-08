import Testing
import Foundation

@Suite("Rest timer cancellation safety")
struct RestTimerCancellationTests {

    @Test("Cancelled sleep does not nil out restEndDate")
    func cancelledSleepPreservesValue() async {
        let state = RestTimerState()
        let newEnd = Date().addingTimeInterval(90)
        await state.set(newEnd)

        let task = Task {
            guard let restEnd = await state.value else { return }
            let remaining = restEnd.timeIntervalSinceNow
            guard remaining > 0 else {
                await state.set(nil)
                return
            }
            do {
                try await Task.sleep(for: .seconds(remaining))
                await state.set(nil)
            } catch {}
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        try? await Task.sleep(for: .milliseconds(50))

        let finalValue = await state.value
        #expect(finalValue != nil, "Cancelled timer must not nil out restEndDate")
    }

    @Test("Natural expiry nils out restEndDate")
    func naturalExpiryNilsValue() async {
        let state = RestTimerState()
        let newEnd = Date().addingTimeInterval(0.1)
        await state.set(newEnd)

        let task = Task {
            guard let restEnd = await state.value else { return }
            let remaining = restEnd.timeIntervalSinceNow
            guard remaining > 0 else {
                await state.set(nil)
                return
            }
            do {
                try await Task.sleep(for: .seconds(remaining))
                await state.set(nil)
            } catch {}
        }

        _ = await task.result
        let finalValue = await state.value
        #expect(finalValue == nil, "Naturally expired timer should nil out restEndDate")
    }

    @Test("Rapid re-assignment preserves latest value")
    func rapidReassignmentPreservesLatest() async {
        let state = RestTimerState()

        var tasks: [Task<Void, Never>] = []
        for i in 0..<5 {
            let end = Date().addingTimeInterval(Double(90 + i))
            await state.set(end)

            let task = Task {
                guard let restEnd = await state.value else { return }
                let remaining = restEnd.timeIntervalSinceNow
                guard remaining > 0 else {
                    await state.set(nil)
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(remaining))
                    await state.set(nil)
                } catch {}
            }
            tasks.last?.cancel()
            tasks.append(task)
            try? await Task.sleep(for: .milliseconds(10))
        }

        try? await Task.sleep(for: .milliseconds(100))

        let finalValue = await state.value
        #expect(finalValue != nil, "After rapid re-assignments, restEndDate must not be nil")

        tasks.last?.cancel()
    }
}

private actor RestTimerState {
    var value: Date?

    func set(_ newValue: Date?) {
        value = newValue
    }
}
