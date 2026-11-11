import Foundation

@testable import NSG

/// Advances production deadlines without sleeping or using the system clock.
@MainActor
final class ManualCameraScheduler: CameraScheduling {
    private struct Job {
        let deadline: Date
        let timer: CameraTimer
        let action: @MainActor () -> Void
    }

    private(set) var now = Date(timeIntervalSince1970: 1_793_703_600)
    private var jobs: [Job] = []

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) -> CameraTimer {
        let timer = CameraTimer()
        jobs.append(Job(deadline: now.addingTimeInterval(seconds), timer: timer, action: action))
        return timer
    }

    func advance(by seconds: TimeInterval) {
        let destination = now.addingTimeInterval(seconds)
        while let index = jobs.indices.filter({ jobs[$0].deadline <= destination })
            .min(by: { jobs[$0].deadline < jobs[$1].deadline })
        {
            let job = jobs.remove(at: index)
            now = job.deadline
            if !job.timer.isCancelled {
                job.action()
            }
        }
        now = destination
    }
}
