import CoreBluetooth

/// Snapshot created after characteristic discovery; determines handshake support and whether a full GEO payload
/// can be written.
struct NikonCameraCapabilities {
    let properties: [NikonCharacteristic: CBCharacteristicProperties]
    let maximumWriteLength: Int

    var supportsHandshake: Bool {
        let pair = properties[.pairing] ?? []
        return pair.contains([.write, .indicate]) && !pair.contains(.notify) &&
            properties[.success]?.contains(.notify) == true &&
            properties[.controllerName]?.contains(.write) == true &&
            maximumWriteLength >= 32
    }

    var supportsLocation: Bool {
        properties[.location]?.contains(.write) == true && maximumWriteLength >= 41
    }
}
