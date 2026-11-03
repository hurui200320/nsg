import Foundation
import CoreLocation

enum LocationQuality {
    static let maximumAge: TimeInterval = 30
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 20

    static func isUsable(_ location: CLLocation, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return CLLocationCoordinate2DIsValid(location.coordinate) &&
            location.coordinate.latitude.isFinite &&
            location.coordinate.longitude.isFinite &&
            location.horizontalAccuracy.isFinite &&
            location.horizontalAccuracy >= 0 &&
            location.horizontalAccuracy <= maximumHorizontalAccuracy &&
            location.verticalAccuracy.isFinite &&
            location.verticalAccuracy >= 0 &&
            location.altitude.isFinite &&
            (-65535...65535).contains(location.altitude) &&
            age.isFinite && age >= -5 && age <= maximumAge
    }
}
