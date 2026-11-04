import Foundation
import CoreBluetooth
import CoreLocation
import Testing
@testable import NSG

@MainActor
final class ManualCameraScheduler: CameraScheduling {
    private struct Job {
        let deadline: Date
        let timer: CameraTimer
        let action: @MainActor () -> Void
    }

    private(set) var now = Date(timeIntervalSince1970: 1_793_703_600)
    private var jobs: [Job] = []

    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () -> Void) -> CameraTimer {
        let timer = CameraTimer()
        jobs.append(Job(deadline: now.addingTimeInterval(seconds), timer: timer, action: action))
        return timer
    }

    func advance(by seconds: TimeInterval) {
        let destination = now.addingTimeInterval(seconds)
        while let index = jobs.indices.filter({ jobs[$0].deadline <= destination })
            .min(by: { jobs[$0].deadline < jobs[$1].deadline }) {
            let job = jobs.remove(at: index)
            now = job.deadline
            if !job.timer.isCancelled { job.action() }
        }
        now = destination
    }
}

@MainActor
final class FakeCameraTransport: CameraTransport {
    var onEvent: ((CameraTransportEvent) -> Void)?
    private(set) var prepareCount = 0
    private(set) var scans: [CameraScanMode] = []
    private(set) var connections: [(CameraDevice, UUID)] = []
    private(set) var disconnections: [UUID] = []
    private(set) var writes: [(NikonCharacteristic, Data)] = []
    private(set) var reads: [NikonCharacteristic] = []
    private(set) var subscriptions: [NikonCharacteristic] = []

    func prepare() { prepareCount += 1 }
    func setForeground(_ isForeground: Bool) {}
    func startScan(mode: CameraScanMode) {
        scans.append(mode)
        onEvent?(.scanningChanged(true))
    }
    func stopScan() { onEvent?(.scanningChanged(false)) }
    func connect(_ device: CameraDevice, sessionID: UUID) { connections.append((device, sessionID)) }
    func disconnect(sessionID: UUID) { disconnections.append(sessionID) }
    func subscribe(_ characteristic: NikonCharacteristic, sessionID: UUID) {
        subscriptions.append(characteristic)
    }
    func read(_ characteristic: NikonCharacteristic, sessionID: UUID) { reads.append(characteristic) }
    func write(_ data: Data, to characteristic: NikonCharacteristic, sessionID: UUID) {
        writes.append((characteristic, data))
    }
    func emit(_ event: CameraTransportEvent) { onEvent?(event) }
}

@MainActor
final class FakeLocationSource: LocationProviding {
    private(set) var isRunning = false
    var latestLocation: CLLocation?
    var hasFullAccuracy = true
    var status: LocationStatus = .off
    var maximumHorizontalAccuracy = LocationQuality.maximumHorizontalAccuracy
    private var onLocation: (@MainActor (CLLocation) -> Void)?

    func start(onLocation: @escaping @MainActor (CLLocation) -> Void) {
        isRunning = true
        self.onLocation = onLocation
    }
    func stop() { isRunning = false; onLocation = nil }
    func emit(_ location: CLLocation) {
        latestLocation = location
        onLocation?(location)
    }
}

@MainActor
final class CameraTestContext {
    let suite = "NSGTests.camera.\(UUID().uuidString)"
    let defaults: UserDefaults
    let transport = FakeCameraTransport()
    let scheduler = ManualCameraScheduler()
    let location = FakeLocationSource()
    let service: NikonCameraService
    let services: AppServiceController

    init(cameras: [NikonCameraRecord] = [],
         bluetoothEnabled: Bool = true,
         locationEnabled: Bool = true,
         picker: @escaping @MainActor () async -> NikonAccessoryPicker.Outcome = { .cancelled }) throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        try NikonCameraStore(defaults: defaults).save(cameras)
        service = NikonCameraService(
            defaults: defaults, transport: transport, scheduler: scheduler,
            locationSource: location, presentPicker: picker,
            makeStage1: { _ in Self.stage1 }
        )
        services = AppServiceController(cameraService: service, isBluetoothEnabled: bluetoothEnabled,
                                        isLocationEnabled: locationEnabled, defaults: defaults)
        services.setLocationEnabled(locationEnabled)
    }

    func cleanup() {
        services.setLocationEnabled(false)
        services.setBluetoothEnabled(false)
        defaults.removePersistentDomain(forName: suite)
    }

    static let stage1 = NikonPairingMessage(stage: 1, timestamp: 0x677DA144EC13E1DB,
                                            device: 0x3C3AE501, nonce: 0x3FDAA451)
    static let stage2 = NikonPairingMessage(stage: 2, timestamp: 0xB9943D5E8026FA29,
                                            device: 0xA8B3F2E4, nonce: 0x16D56A13)

    static func camera(connectedAt: Date? = nil, device: UInt32 = 0x11223301) -> NikonCameraRecord {
        let id = UUID()
        return NikonCameraRecord(id: id, peripheralIdentifier: id, name: "Z5",
                                 controllerDevice: device, controllerNonce: 42,
                                 pairingCompletedAt: Date(timeIntervalSince1970: 100),
                                 lastConnectedAt: connectedAt)
    }

    @discardableResult
    func connect(firstPairing: Bool = false) throws -> UUID {
        transport.emit(.stateChanged(.poweredOn))
        let device = CameraDevice(id: UUID(), name: "Z5")
        service.connect(device, firstPairing: firstPairing)
        let session = try #require(transport.connections.last?.1)
        transport.emit(.discovering(session))
        transport.emit(.connected(session, CameraCapabilities(properties: [
            .pairing: [.write, .indicate, .read], .success: [.notify],
            .controllerName: [.write], .location: [.write]
        ], maximumWriteLength: 512)))
        transport.emit(.subscriptionChanged(session, .pairing, true, nil))
        transport.emit(.subscriptionChanged(session, .success, true, nil))
        return session
    }

    func finishHandshake(_ session: UUID) {
        transport.emit(.writeCompleted(session, .pairing, nil))
        transport.emit(.valueReceived(session, .pairing, Self.stage2.data))
        transport.emit(.writeCompleted(session, .pairing, nil))
        transport.emit(.valueReceived(session, .pairing,
                                      NikonPairingMessage(stage: 4, timestamp: 0, device: 0, nonce: 0).data))
        transport.emit(.valueReceived(session, .success, Data([1, 0])))
        transport.emit(.writeCompleted(session, .controllerName, nil))
    }

    func fix(age: TimeInterval = 0) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.5, longitude: 139.75),
                   altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 8,
                   timestamp: scheduler.now.addingTimeInterval(-age))
    }
}
