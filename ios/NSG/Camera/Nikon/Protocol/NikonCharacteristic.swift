import CoreBluetooth

/// Maps handshake and GEO characteristics to fixed UUIDs for service commands and transport lookup.
enum NikonCharacteristic: CaseIterable {
    case pairing
    case success
    case controllerName
    case location

    static let serviceUUID = CBUUID(string: "0000DE00-3DD4-4255-8D62-6DC7B9BD5561")

    var uuid: CBUUID {
        let word: String
        switch self {
        case .pairing: word = "2000"
        case .success: word = "2008"
        case .controllerName: word = "2002"
        case .location: word = "2007"
        }
        return CBUUID(string: "0000\(word)-3DD4-4255-8D62-6DC7B9BD5561")
    }

    init?(uuid: CBUUID) {
        guard let value = Self.allCases.first(where: { $0.uuid == uuid }) else { return nil }
        self = value
    }
}
