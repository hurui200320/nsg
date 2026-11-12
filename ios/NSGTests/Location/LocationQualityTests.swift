import CoreLocation
import Foundation
import Testing

@testable import NSG

@MainActor
struct LocationQualityTests {
    private let now = Date(timeIntervalSince1970: 1_793_703_600)

    @Test(
        "Fix age accepts five seconds ahead through thirty seconds old",
        arguments: [(-6.0, false), (-5.0, true), (30.0, true), (31.0, false)]
    )
    func fixAgeRespectsFreshnessWindow(age: TimeInterval, isUsable: Bool) {
        let fix = location(age: age)

        #expect(LocationQuality.isUsable(fix, now: now) == isUsable)
        #expect(LocationQuality.rejection(for: fix, now: now) == (isUsable ? nil : .stale))
    }

    @Test(
        "Horizontal accuracy must be nonnegative and within the configured maximum",
        arguments: [(-1.0, false), (0.0, true), (20.0, true), (21.0, false)]
    )
    func horizontalAccuracyRespectsThreshold(accuracy: Double, isUsable: Bool) {
        let rejection = LocationQuality.rejection(for: location(horizontalAccuracy: accuracy), now: now)

        #expect(rejection == (isUsable ? nil : .horizontalAccuracy(maximum: 20)))
    }

    @Test("Invalid coordinates report the coordinate rejection")
    func invalidCoordinatesReportReason() {
        let rejection = LocationQuality.rejection(for: location(latitude: 91), now: now)

        #expect(rejection == .invalidCoordinates)
    }

    @Test("Altitude needs valid vertical accuracy and must fit the GEO encoding")
    func altitudeRequiresValidAccuracyAndEncodableRange() {
        #expect(LocationQuality.rejection(for: location(verticalAccuracy: -1), now: now) == .altitude)
        #expect(LocationQuality.rejection(for: location(altitude: 65536), now: now) == .altitude)
        #expect(LocationQuality.isUsable(location(altitude: -65535), now: now))
        #expect(LocationQuality.isUsable(location(altitude: 65535), now: now))
    }

    private func location(
        latitude: Double = 35.5,
        altitude: Double = 10,
        horizontalAccuracy: Double = 5,
        verticalAccuracy: Double = 8,
        age: TimeInterval = 0
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 139.75),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: now.addingTimeInterval(-age)
        )
    }
}
