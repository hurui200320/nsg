import Foundation
import Observation

enum LocationSendInterval: TimeInterval, CaseIterable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    var title: String {
        switch self {
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        }
    }
}

/// Owns app-level service switches; these express user intent, not system power, authorization, or runtime state.
@MainActor
@Observable
final class AppServiceController {
    private(set) var isBluetoothEnabled: Bool
    private(set) var isLocationEnabled: Bool
    private(set) var isNearbyScanningEnabled: Bool
    private(set) var isMapPreviewEnabled: Bool
    private(set) var locationSendInterval: LocationSendInterval
    private(set) var locationAccuracy: LocationAccuracy
    let cameraService: NikonCameraService
    @ObservationIgnored private let defaults: UserDefaults

    private enum SettingsKey {
        static let nearbyScanning = "settings.nearbyScanning"
        static let mapPreview = "settings.mapPreview"
        static let sendInterval = "settings.locationSendInterval"
        static let accuracy = "settings.locationAccuracy"
    }

    var locationService: any LocationProviding { cameraService.locationService }

    /// Builds and binds services without requesting permission; call startEnabledServices when the app appears.
    init(cameraService: NikonCameraService? = nil,
         isBluetoothEnabled: Bool = true,
         isLocationEnabled: Bool = true,
         defaults: UserDefaults = .standard) {
        self.cameraService = cameraService ?? NikonCameraService()
        self.isBluetoothEnabled = isBluetoothEnabled
        self.isLocationEnabled = isLocationEnabled
        self.defaults = defaults
        isNearbyScanningEnabled = defaults.object(forKey: SettingsKey.nearbyScanning) as? Bool ?? true
        isMapPreviewEnabled = defaults.object(forKey: SettingsKey.mapPreview) as? Bool ?? true
        locationSendInterval = LocationSendInterval(rawValue: defaults.double(forKey: SettingsKey.sendInterval)) ?? .tenSeconds
        locationAccuracy = LocationAccuracy(rawValue: defaults.double(forKey: SettingsKey.accuracy)) ?? .twentyMeters
        self.cameraService.setNearbyScanningEnabled(isNearbyScanningEnabled)
        self.cameraService.locationSync.sendInterval = locationSendInterval.rawValue
        self.cameraService.locationService.maximumHorizontalAccuracy = locationAccuracy.rawValue
        self.cameraService.isBluetoothAllowed = { [weak self] in self?.isBluetoothEnabled == true }
        self.cameraService.locationSync.isLocationAllowed = { [weak self] in self?.isLocationEnabled == true }
    }

    /// Applies initial intent when the app appears; GPS acquisition does not require a connected camera.
    func startEnabledServices() {
        if isBluetoothEnabled { cameraService.prepare() }
        if isLocationEnabled { startLocation() }
    }

    /// Applies the app Bluetooth switch; the system picker must finish before Bluetooth use can stop.
    func setBluetoothEnabled(_ enabled: Bool) {
        guard !cameraService.isPairingPickerPresented else { return }
        isBluetoothEnabled = enabled
        if enabled {
            cameraService.prepare()
        } else {
            cameraService.stopBluetooth()
        }
    }

    /// Applies the app GPS switch independently of camera connections; pending writes may still be acknowledged.
    func setLocationEnabled(_ enabled: Bool) {
        isLocationEnabled = enabled
        if enabled {
            startLocation()
        } else {
            locationService.stop()
        }
    }

    func setNearbyScanningEnabled(_ enabled: Bool) {
        isNearbyScanningEnabled = enabled
        defaults.set(enabled, forKey: SettingsKey.nearbyScanning)
        cameraService.setNearbyScanningEnabled(enabled)
    }

    func setMapPreviewEnabled(_ enabled: Bool) {
        isMapPreviewEnabled = enabled
        defaults.set(enabled, forKey: SettingsKey.mapPreview)
    }

    func setLocationSendInterval(_ interval: LocationSendInterval) {
        locationSendInterval = interval
        defaults.set(interval.rawValue, forKey: SettingsKey.sendInterval)
        cameraService.locationSync.sendInterval = interval.rawValue
    }

    func setLocationAccuracy(_ accuracy: LocationAccuracy) {
        locationAccuracy = accuracy
        defaults.set(accuracy.rawValue, forKey: SettingsKey.accuracy)
        locationService.maximumHorizontalAccuracy = accuracy.rawValue
    }

    private func startLocation() {
        guard !locationService.isRunning else { return }
        let sync = cameraService.locationSync
        sync.resumeSending()
        locationService.start { [weak sync] location in
            sync?.send(location, bypassInterval: false)
        }
    }
}
