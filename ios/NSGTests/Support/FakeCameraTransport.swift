import Foundation

@testable import NSG

@MainActor
final class FakeCameraTransport: CameraTransport {
    var onEvent: ((CameraTransportEvent) -> Void)?
    private(set) var prepareCount = 0
    private(set) var scans: [CameraScanMode] = []
    private(set) var connections: [(device: CameraDevice, sessionID: UUID)] = []
    private(set) var disconnections: [UUID] = []
    private(set) var writes: [(characteristic: NikonCharacteristic, data: Data)] = []
    private(set) var reads: [NikonCharacteristic] = []
    private(set) var subscriptions: [NikonCharacteristic] = []

    func prepare() {
        prepareCount += 1
    }

    func setForeground(_ isForeground: Bool) {}

    func startScan(mode: CameraScanMode) {
        scans.append(mode)
        onEvent?(.scanningChanged(true))
    }

    func stopScan() {
        onEvent?(.scanningChanged(false))
    }

    func connect(_ device: CameraDevice, sessionID: UUID) {
        connections.append((device, sessionID))
    }

    func disconnect(sessionID: UUID) {
        disconnections.append(sessionID)
    }

    func subscribe(_ characteristic: NikonCharacteristic, sessionID: UUID) {
        subscriptions.append(characteristic)
    }

    func read(_ characteristic: NikonCharacteristic, sessionID: UUID) {
        reads.append(characteristic)
    }

    func write(_ data: Data, to characteristic: NikonCharacteristic, sessionID: UUID) {
        writes.append((characteristic, data))
    }

    func writes(to characteristic: NikonCharacteristic) -> [Data] {
        writes.filter { $0.characteristic == characteristic }.map(\.data)
    }

    func emit(_ event: CameraTransportEvent) {
        onEvent?(event)
    }
}
