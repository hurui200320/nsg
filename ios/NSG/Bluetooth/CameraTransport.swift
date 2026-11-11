import Foundation

enum CameraScanMode: Equatable {
    case discovery
    case reconnection
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
