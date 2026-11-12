import CoreBluetooth
import CoreLocation
import Foundation
import Testing

@testable import NSG

@MainActor
final class CameraTestContext {
    let suiteName = "NSGTests.camera.\(UUID().uuidString)"
    let defaults: UserDefaults
    let transport = FakeCameraTransport()
    let scheduler = ManualCameraScheduler()
    let location = FakeLocationSource()
    let service: NikonCameraService
    let services: AppServiceController

    init(
        cameras: [NikonCameraRecord] = [],
        bluetoothEnabled: Bool = true,
        locationEnabled: Bool = true,
        startsLocation: Bool = true,
        picker: @escaping @MainActor () async -> NikonAccessoryPicker.Outcome = { .cancelled }
    ) throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        try NikonCameraStore(defaults: defaults).save(cameras)
        service = NikonCameraService(
            defaults: defaults,
            transport: transport,
            scheduler: scheduler,
            locationSource: location,
            presentPicker: picker,
            makeStage1: { _ in Self.stage1 }
        )
        services = AppServiceController(
            cameraService: service,
            isBluetoothEnabled: bluetoothEnabled,
            isLocationEnabled: locationEnabled,
            defaults: defaults
        )
        // Most service tests begin with GPS acquisition already enabled by the app.
        if startsLocation {
            services.setLocationEnabled(locationEnabled)
        }
    }

    func cleanup() {
        services.setLocationEnabled(false)
        services.setBluetoothEnabled(false)
        defaults.removePersistentDomain(forName: suiteName)
    }

    static let stage1 = NikonPairingMessage(
        stage: 1,
        timestamp: 0x677D_A144_EC13_E1DB,
        device: 0x3C3A_E501,
        nonce: 0x3FDA_A451
    )
    static let stage2 = NikonPairingMessage(
        stage: 2,
        timestamp: 0xB994_3D5E_8026_FA29,
        device: 0xA8B3_F2E4,
        nonce: 0x16D5_6A13
    )
    static let stage4 = NikonPairingMessage(stage: 4, timestamp: 0, device: 0, nonce: 0)
    static let capabilities = NikonCameraCapabilities(
        properties: [
            .pairing: [.write, .indicate, .read],
            .success: [.notify],
            .controllerName: [.write],
            .location: [.write],
        ],
        maximumWriteLength: 512
    )

    static func camera(connectedAt: Date? = nil, device: UInt32 = 0x1122_3301) -> NikonCameraRecord {
        let id = UUID()
        return NikonCameraRecord(
            id: id,
            peripheralIdentifier: id,
            name: "Z5",
            controllerDevice: device,
            controllerNonce: 42,
            pairingCompletedAt: Date(timeIntervalSince1970: 100),
            lastConnectedAt: connectedAt
        )
    }

    @discardableResult
    func connect(
        firstPairing: Bool = false,
        capabilities: NikonCameraCapabilities? = nil
    ) throws -> UUID {
        transport.emit(.stateChanged(.poweredOn))
        let device = CameraDevice(id: UUID(), name: "Z5")
        service.connect(device, firstPairing: firstPairing)
        let session = try #require(transport.connections.last?.sessionID)
        discoverAndSubscribe(session, capabilities: capabilities)
        return session
    }

    /// Completes transport discovery for a session that was already requested by the service.
    func discoverAndSubscribe(_ session: UUID, capabilities: NikonCameraCapabilities? = nil) {
        transport.emit(.discovering(session))
        transport.emit(.connected(session, capabilities ?? Self.capabilities))
        transport.emit(.subscriptionChanged(session, .pairing, true, nil))
        transport.emit(.subscriptionChanged(session, .success, true, nil))
    }

    func finishHandshake(_ session: UUID) {
        transport.emit(.writeCompleted(session, .pairing, nil))
        transport.emit(.valueReceived(session, .pairing, Self.stage2.data))
        transport.emit(.writeCompleted(session, .pairing, nil))
        transport.emit(.valueReceived(session, .pairing, Self.stage4.data))
        transport.emit(.valueReceived(session, .success, Data([1, 0])))
        transport.emit(.writeCompleted(session, .controllerName, nil))
    }

    func fix(age: TimeInterval = 0, horizontalAccuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.5, longitude: 139.75),
            altitude: 10,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 8,
            timestamp: scheduler.now.addingTimeInterval(-age)
        )
    }
}

/// Waits for the injected system picker task to settle. Camera deadlines use ManualCameraScheduler instead.
@MainActor
func waitUntil(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
        try #require(
            ContinuousClock.now < deadline,
            "Timed out waiting for the pairing picker task.",
            sourceLocation: sourceLocation
        )
        try await Task.sleep(for: .milliseconds(1))
    }
}
