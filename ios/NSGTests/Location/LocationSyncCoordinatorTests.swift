import CoreLocation
import Foundation
import Testing

@testable import NSG

@MainActor
struct LocationSyncCoordinatorTests {
    @Test("Only acknowledgement records a successful fix and starts the automatic send interval")
    func acknowledgementRecordsFixAndControlsThrottle() {
        let source = FakeLocationSource()
        let scheduler = ManualCameraScheduler()
        let coordinator = makeCoordinator(source: source, scheduler: scheduler)
        let fix = location(at: scheduler.now)
        var payloads: [Data] = []
        coordinator.submit = { payloads.append($0) }

        #expect(coordinator.send(fix, bypassInterval: false))
        #expect(coordinator.transferState == .sending)
        #expect(coordinator.lastSentAt == nil)
        #expect(coordinator.lastSentLocation == nil)
        #expect(!coordinator.send(fix))

        scheduler.advance(by: 2)
        coordinator.acknowledge(error: nil)
        #expect(coordinator.transferState == .sent)
        #expect(coordinator.lastSentAt == scheduler.now)
        #expect(coordinator.lastSentLocation === fix)

        scheduler.advance(by: 9)
        #expect(!coordinator.send(location(at: scheduler.now), bypassInterval: false))
        scheduler.advance(by: 1)
        #expect(coordinator.send(location(at: scheduler.now), bypassInterval: false))
        #expect(payloads.count == 2)
    }

    @Test("An ordinary write error pauses further sends until the next camera session")
    func ordinaryWriteFailurePausesUntilConnectionReset() {
        let source = FakeLocationSource()
        let scheduler = ManualCameraScheduler()
        let coordinator = makeCoordinator(source: source, scheduler: scheduler)
        var recoveryFailures: [CameraFailure] = []
        coordinator.onConnectionFailure = { recoveryFailures.append($0) }
        let failure = CameraFailure("Write failed.")

        #expect(coordinator.send(location(at: scheduler.now)))
        coordinator.acknowledge(error: failure)
        #expect(coordinator.transferState == .failed(failure.diagnosticDescription))
        #expect(coordinator.lastSentAt == nil)
        #expect(!coordinator.send(location(at: scheduler.now)))

        scheduler.advance(by: 15)
        #expect(recoveryFailures.isEmpty)
        coordinator.resetForConnection()
        #expect(coordinator.transferState == .idle)
        #expect(coordinator.send(location(at: scheduler.now)))
    }

    @Test("Reduced accuracy or a missing fix prevents manual and connection-ready sends")
    func currentLocationRequiresPreciseAvailableFix() {
        let source = FakeLocationSource()
        let scheduler = ManualCameraScheduler()
        let coordinator = makeCoordinator(source: source, scheduler: scheduler)
        var payloads: [Data] = []
        coordinator.submit = { payloads.append($0) }

        coordinator.sendCurrentLocation()
        #expect(payloads.isEmpty)
        source.latestLocation = location(at: scheduler.now)
        source.hasFullAccuracy = false
        coordinator.connectionReady()
        coordinator.sendCurrentLocation()
        #expect(payloads.isEmpty)

        source.hasFullAccuracy = true
        coordinator.sendCurrentLocation()
        #expect(payloads.count == 1)
        #expect(coordinator.transferState == .sending)
    }

    private func makeCoordinator(
        source: FakeLocationSource,
        scheduler: ManualCameraScheduler
    ) -> LocationSyncCoordinator {
        source.start { _ in }
        let coordinator = LocationSyncCoordinator(source: source, scheduler: scheduler)
        coordinator.isAvailable = { true }
        return coordinator
    }

    private func location(at date: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.5, longitude: 139.75),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 8,
            timestamp: date
        )
    }
}
