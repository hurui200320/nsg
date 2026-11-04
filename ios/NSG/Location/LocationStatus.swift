import Foundation
import CoreLocation

/// Location acquisition and authorization diagnostics for the UI, separate from whether the camera acknowledged
/// a GEO write.
enum LocationStatus: Equatable {
    case off
    case waiting
    case servicesDisabled
    case authorizationDenied
    case requestingAuthorization
    case accuracyLimited
    case ready
    case rejected(LocationQuality.Rejection)
    case failed(String)

    var message: String {
        switch self {
        case .off: "Location sharing is off."
        case .waiting: "Waiting for a GPS fix. Try moving outdoors."
        case .servicesDisabled: "Enable Location Services in Settings."
        case .authorizationDenied: "Allow location access in Settings."
        case .requestingAuthorization: "Allow location access to send GPS to your camera."
        case .accuracyLimited: "Enable Precise Location in Settings."
        case .ready: "Precise location available."
        case .rejected(let reason): reason.message
        case .failed(let message): "Location failed: \(message)"
        }
    }
}

/// Location interface used by the sync layer; both live acquisition and test sources provide fixes and
/// diagnostics through it.
@MainActor
protocol LocationProviding: AnyObject {
    var isRunning: Bool { get }
    var latestLocation: CLLocation? { get }
    var hasFullAccuracy: Bool { get }
    var status: LocationStatus { get }
    var maximumHorizontalAccuracy: CLLocationAccuracy { get set }
    func start(onLocation: @escaping @MainActor (CLLocation) -> Void)
    func stop()
}
