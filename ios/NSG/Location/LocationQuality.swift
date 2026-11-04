import Foundation
import CoreLocation

/// Maximum reported horizontal error accepted for sending a fix.
enum LocationAccuracy: CLLocationAccuracy, CaseIterable {
    case tenMeters = 10
    case twentyMeters = 20
    case fiftyMeters = 50
    case hundredMeters = 100
}

/// Quality policy shared by acquisition and sending; recheck before encoding because a waiting fix may have
/// expired.
enum LocationQuality {
    enum Rejection: Equatable {
        case invalidCoordinates
        case stale
        case horizontalAccuracy(maximum: CLLocationAccuracy)
        case altitude

        var message: String {
            switch self {
            case .invalidCoordinates: "Waiting for valid GPS coordinates."
            case .stale: "Waiting for a fresh GPS fix."
            case .horizontalAccuracy(let maximum): "Waiting for horizontal accuracy within \(Int(maximum)) m."
            case .altitude: "Waiting for a valid altitude within the camera's encoding range."
            }
        }
    }

    static let maximumAge: TimeInterval = 30
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 20

    /// Checks coordinates, age, accuracy, and altitude on receipt or send; nil means usable, and now is
    /// injectable for tests.
    static func rejection(for location: CLLocation, now: Date = Date(),
                          maximumHorizontalAccuracy: CLLocationAccuracy = maximumHorizontalAccuracy) -> Rejection? {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.coordinate.latitude.isFinite, location.coordinate.longitude.isFinite else {
            return .invalidCoordinates
        }
        let age = now.timeIntervalSince(location.timestamp)
        guard age.isFinite, age >= -5, age <= maximumAge else { return .stale }
        guard location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return .horizontalAccuracy(maximum: maximumHorizontalAccuracy)
        }
        guard location.verticalAccuracy.isFinite, location.verticalAccuracy >= 0,
              location.altitude.isFinite, (-65535...65535).contains(location.altitude) else { return .altitude }
        return nil
    }

    static func isUsable(_ location: CLLocation, now: Date = Date()) -> Bool {
        rejection(for: location, now: now) == nil
    }
}
