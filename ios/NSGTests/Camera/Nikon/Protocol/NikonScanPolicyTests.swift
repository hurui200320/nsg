import CoreBluetooth
import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonScanPolicyTests {
    @Test("Foreground target rediscovery omits service filtering; other scans require the Nikon service")
    func scanFiltersDependOnModeAndForegroundState() {
        let service = [NikonCharacteristic.serviceUUID]

        #expect(NikonScanPolicy.services(for: .discovery, isForeground: true) == service)
        #expect(NikonScanPolicy.services(for: .discovery, isForeground: false) == service)
        #expect(NikonScanPolicy.services(for: .reconnection, isForeground: true) == nil)
        #expect(NikonScanPolicy.services(for: .reconnection, isForeground: false) == service)
    }

    @Test("A Nikon service UUID or Nikon manufacturer prefix allows advertisement discovery")
    func advertisementsRequireNikonServiceOrManufacturer() {
        #expect(
            NikonScanPolicy.isNikonAdvertisement(
                services: [NikonCharacteristic.serviceUUID],
                manufacturerData: nil
            )
        )
        #expect(
            NikonScanPolicy.isNikonAdvertisement(
                services: [],
                manufacturerData: Data([0x99, 0x03, 1, 0, 0, 0, 0])
            )
        )
        #expect(
            !NikonScanPolicy.isNikonAdvertisement(
                services: [],
                manufacturerData: Data([0x98, 0x03, 1, 0, 0, 0, 0])
            )
        )
        #expect(!NikonScanPolicy.isNikonAdvertisement(services: [], manufacturerData: nil))
    }
}
