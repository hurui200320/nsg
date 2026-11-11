import Foundation
import CoreBluetooth

enum NikonScanPolicy {
    /// Selects filters before scanning; foreground reconnection can omit service UUIDs, while background
    /// scanning must specify them.
    static func services(for mode: CameraScanMode, isForeground: Bool) -> [CBUUID]? {
        // Nikon reconnect advertisements may omit the service UUID. iOS requires
        // a service filter in the background, so broad rediscovery is foreground-only.
        mode == .reconnection && isForeground ? nil : [NikonCharacteristic.serviceUUID]
    }

    /// Filters Nikon advertisements before listing discoveries; passing this check does not establish the
    /// target camera's identity.
    static func isNikonAdvertisement(services: [CBUUID], manufacturerData: Data?) -> Bool {
        if services.contains(NikonCharacteristic.serviceUUID) { return true }
        guard let manufacturerData else { return false }
        return manufacturerData.starts(with: [0x99, 0x03])
    }
}
