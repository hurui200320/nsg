import Foundation

/// Cancellation handle for a scheduled action; cancel when its flow ends or its deadline is replaced. Repeated
/// cancellation is safe.
@MainActor
final class CameraTimer {
    private(set) var isCancelled = false
    fileprivate var onCancel: (() -> Void)?

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel?()
        onCancel = nil
    }
}

/// Provides current time and delayed execution; uses the system clock in production and a manually advanced
/// clock in tests.
@MainActor
protocol CameraScheduling {
    var now: Date { get }
    /// Schedules one main-actor action; callers must retain the returned handle and cancel it when the flow is
    /// invalidated.
    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) -> CameraTimer
}

@MainActor
struct SystemCameraScheduler: CameraScheduling {
    var now: Date { Date() }

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) -> CameraTimer {
        let timer = CameraTimer()
        let task = Task { @MainActor [weak timer] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let timer, !timer.isCancelled else { return }
            timer.onCancel = nil
            action()
        }
        timer.onCancel = { task.cancel() }
        return timer
    }
}
