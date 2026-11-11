import CoreLocation

@testable import NSG

/// Delivers the fix requested by each test so the coordinator's quality checks remain observable.
@MainActor
final class FakeLocationSource: LocationProviding {
    private(set) var isRunning = false
    var latestLocation: CLLocation?
    // Tests select reduced accuracy explicitly; the fake never requests system authorization.
    var hasFullAccuracy = true
    var status: LocationStatus = .off
    var maximumHorizontalAccuracy = LocationQuality.maximumHorizontalAccuracy
    private var onLocation: (@MainActor (CLLocation) -> Void)?

    func start(onLocation: @escaping @MainActor (CLLocation) -> Void) {
        isRunning = true
        self.onLocation = onLocation
    }

    func stop() {
        isRunning = false
        latestLocation = nil
        onLocation = nil
    }

    func emit(_ location: CLLocation) {
        latestLocation = location
        onLocation?(location)
    }
}
