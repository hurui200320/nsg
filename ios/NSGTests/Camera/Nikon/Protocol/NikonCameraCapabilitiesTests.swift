import CoreBluetooth
import Testing

@testable import NSG

@MainActor
struct NikonCameraCapabilitiesTests {
    @Test(
        "Handshake and GEO require payload capacities of 32 and 41 bytes",
        arguments: [(31, false, false), (32, true, false), (40, true, false), (41, true, true)]
    )
    func writeCapacityGatesSupportedOperations(
        length: Int,
        supportsHandshake: Bool,
        supportsLocation: Bool
    ) {
        let capabilities = NikonCameraCapabilities(
            properties: CameraTestContext.capabilities.properties,
            maximumWriteLength: length
        )

        #expect(capabilities.supportsHandshake == supportsHandshake)
        #expect(capabilities.supportsLocation == supportsLocation)
    }

    @Test(
        "Each handshake characteristic must be present",
        arguments: [NikonCharacteristic.pairing, .success, .controllerName]
    )
    func missingCharacteristicPreventsHandshake(_ characteristic: NikonCharacteristic) {
        var properties = CameraTestContext.capabilities.properties
        properties.removeValue(forKey: characteristic)
        let capabilities = NikonCameraCapabilities(properties: properties, maximumWriteLength: 512)

        #expect(!capabilities.supportsHandshake)
    }

    @Test(
        "PAIR requires write and indicate without notify",
        arguments: [CBCharacteristicProperties.write, [.write, .notify], [.write, .indicate, .notify]]
    )
    func incompatiblePairPropertiesPreventHandshake(_ pairProperties: CBCharacteristicProperties) {
        var properties = CameraTestContext.capabilities.properties
        properties[.pairing] = pairProperties
        let capabilities = NikonCameraCapabilities(properties: properties, maximumWriteLength: 512)

        #expect(!capabilities.supportsHandshake)
    }

    @Test("A camera can support handshake without a writable GEO characteristic")
    func missingLocationWriteAllowsHandshakeOnly() {
        var properties = CameraTestContext.capabilities.properties
        properties[.location] = [.read]
        let capabilities = NikonCameraCapabilities(properties: properties, maximumWriteLength: 512)

        #expect(capabilities.supportsHandshake)
        #expect(!capabilities.supportsLocation)
    }
}
