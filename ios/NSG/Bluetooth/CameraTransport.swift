import Foundation
import CoreBluetooth

/// Lightweight scan result for UI selection; id is the discovered peripheral UUID, not a stable camera record
/// ID.
struct CameraDevice: Equatable, Identifiable {
    let id: UUID
    let name: String?
}

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

/// Snapshot created after characteristic discovery; determines handshake support and whether a full GEO payload
/// can be written.
struct CameraCapabilities {
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

/// Shared failure description and recovery policy; preserves the underlying error domain and code across
/// retries.
struct CameraFailure: Error, Equatable, LocalizedError {
    enum Recovery { case retry, userAction }

    let message: String
    let domain: String?
    let code: Int?
    let recovery: Recovery

    init(_ message: String, recovery: Recovery = .retry) {
        self.message = message
        self.domain = nil
        self.code = nil
        self.recovery = recovery
    }

    init(error: Error, recovery: Recovery = .retry) {
        let value = error as NSError
        message = value.localizedDescription
        domain = value.domain
        code = value.code
        self.recovery = recovery
    }

    var errorDescription: String? { message }
    /// Checked after GEO write errors; Nikon ATT 0x80 rejection requires disconnection and a new handshake.
    var requiresGeoReconnection: Bool { domain == CBATTErrorDomain && code == 0x80 }

    var diagnosticDescription: String {
        guard let domain, let code else { return message }
        return "\(message) (\(domain), code \(code))"
    }
}

enum CameraScanMode: Equatable {
    case discovery
    case reconnection
}

enum CameraScanPolicy {
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

/// Events delivered to the camera service; connection UUIDs identify sessions, and connected means services and
/// characteristics were discovered.
enum CameraTransportEvent {
    case stateChanged(CBManagerState)
    case scanningChanged(Bool)
    case discovered(CameraDevice, Data?)
    case discovering(UUID)
    case connected(UUID, CameraCapabilities)
    case subscriptionChanged(UUID, NikonCharacteristic, Bool, CameraFailure?)
    case valueReceived(UUID, NikonCharacteristic, Data)
    case writeCompleted(UUID, NikonCharacteristic, CameraFailure?)
    case disconnected(UUID, CameraFailure?)
    case failed(UUID, CameraFailure)
}

/// Communication interface for the camera service; accepts Bluetooth or fake implementations without exposing
/// CoreBluetooth objects.
@MainActor
protocol CameraTransport: AnyObject {
    /// Bound during service initialization; implementations may report events synchronously, so bind before
    /// issuing commands.
    var onEvent: ((CameraTransportEvent) -> Void)? { get set }
    func prepare()
    func setForeground(_ isForeground: Bool)
    func startScan(mode: CameraScanMode)
    func stopScan()
    /// Connects a discovered device; subsequent connection events must carry the sessionID created by the
    /// service.
    func connect(_ device: CameraDevice, sessionID: UUID)
    func disconnect(sessionID: UUID)
    /// Subscribes after characteristic discovery; subscriptionChanged reports whether notifications or
    /// indications were enabled.
    func subscribe(_ characteristic: NikonCharacteristic, sessionID: UUID)
    /// Reads a readable characteristic in the current session; valueReceived delivers the resulting data.
    func read(_ characteristic: NikonCharacteristic, sessionID: UUID)
    /// Submits a payload for the current session; implementations serialize writes and report acknowledgement
    /// through writeCompleted.
    func write(_ data: Data, to characteristic: NikonCharacteristic, sessionID: UUID)
}
