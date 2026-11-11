import CoreBluetooth
import Testing

@testable import NSG

@MainActor
struct AppServiceControllerTests {
    @Test("Enabling GPS acquires without Bluetooth; only a completed handshake permits sending")
    func enablingLocationAcquiresBeforeCameraIsReady() throws {
        let context = try CameraTestContext(bluetoothEnabled: false, locationEnabled: false)
        defer { context.cleanup() }

        context.services.setLocationEnabled(true)
        #expect(context.location.isRunning)
        #expect(!context.services.isBluetoothEnabled)
        #expect(context.transport.prepareCount == 0)
        context.location.emit(context.fix())
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.isEmpty)

        context.services.setBluetoothEnabled(true)
        let session = try context.connect()
        #expect(context.transport.writes(to: .location).isEmpty)
        context.finishHandshake(session)
        #expect(context.transport.writes(to: .location).count == 1)
    }

    @Test("Bluetooth shutdown cancels discovery and retries; late events cannot resume them")
    func disablingBluetoothStopsDiscoveryAndReconnect() throws {
        let target = CameraTestContext.camera(connectedAt: Date(timeIntervalSince1970: 200))
        let context = try CameraTestContext(cameras: [target])
        defer { context.cleanup() }

        context.transport.emit(.stateChanged(.poweredOn))
        #expect(context.service.isScanning)
        let scans = context.transport.scans.count
        context.services.setBluetoothEnabled(false)
        #expect(!context.service.isScanning)
        #expect(!context.service.isAutomaticReconnectEnabled)
        #expect(!NikonAutoReconnectStore(defaults: context.defaults).load(knownCameras: [target]).isEnabled)
        #expect(context.location.isRunning)

        context.transport.emit(.scanningChanged(true))
        context.transport.emit(.discovered(CameraDevice(id: target.peripheralIdentifier, name: target.name), nil))
        context.transport.emit(.stateChanged(.poweredOff))
        context.transport.emit(.stateChanged(.poweredOn))
        context.service.setDiscoveryVisible(true)
        context.scheduler.advance(by: 120)
        #expect(!context.service.isScanning)
        #expect(context.transport.scans.count == scans)
        #expect(context.transport.prepareCount == 0)
        #expect(context.transport.connections.isEmpty)

        context.services.setBluetoothEnabled(true)
        #expect(context.transport.prepareCount == 1)
        #expect(context.service.isScanning)
    }

    @Test("Bluetooth shutdown disconnects the camera without stopping app GPS")
    func disablingBluetoothDisconnectsCameraAndKeepsLocationRunning() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let session = try context.connect()
        context.finishHandshake(session)
        context.services.setBluetoothEnabled(false)
        #expect(context.transport.disconnections == [session])
        #expect(!context.service.canSendLocation)
        #expect(context.location.isRunning)
        let writes = context.transport.writes.count
        context.location.emit(context.fix())
        context.service.sendCurrentLocation()
        #expect(context.transport.writes.count == writes)
        context.transport.emit(.disconnected(session, nil))
        context.scheduler.advance(by: 120)
        #expect(context.service.connectionState == .disconnected)
        #expect(context.transport.scans.isEmpty)
    }

    @Test("GPS shutdown blocks all sends and remains off across camera reconnection")
    func disabledLocationStaysOffAfterCameraReconnects() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let first = try context.connect()
        context.finishHandshake(first)
        context.services.setLocationEnabled(false)
        #expect(!context.location.isRunning)
        #expect(context.service.connectionState == .ready)
        #expect(!context.service.canSendLocation)
        #expect(!context.service.locationSync.send(context.fix()))
        context.service.sendCurrentLocation()
        #expect(context.transport.writes(to: .location).isEmpty)

        context.service.disconnect()
        context.transport.emit(.disconnected(first, nil))
        let second = try context.connect()
        context.finishHandshake(second)
        #expect(!context.services.isLocationEnabled)
        #expect(!context.location.isRunning)
        #expect(context.transport.writes(to: .location).isEmpty)

        context.services.setLocationEnabled(true)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).count == 1)
    }

    @Test("Camera disconnection preserves GPS intent and acquisition; reacquisition is unnecessary")
    func cameraReconnectSendsFixAcquiredWhileDisconnected() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }

        let first = try context.connect()
        context.finishHandshake(first)
        context.transport.emit(.disconnected(first, nil))
        #expect(context.services.isLocationEnabled)
        #expect(context.location.isRunning)
        #expect(!context.service.canSendLocation)
        context.location.emit(context.fix())
        #expect(context.transport.writes(to: .location).isEmpty)

        let second = try context.connect()
        context.finishHandshake(second)
        #expect(context.location.isRunning)
        #expect(context.transport.writes(to: .location).count == 1)
    }

    @Test("Bluetooth cannot be disabled while the system pairing picker is open")
    func disablingBluetoothWaitsForPairingPicker() async throws {
        var finishPicker: (@MainActor () -> Void)?
        let context = try CameraTestContext(picker: {
            await withCheckedContinuation { continuation in
                finishPicker = { continuation.resume(returning: .cancelled) }
            }
        })
        defer { context.cleanup() }

        let session = try context.connect(firstPairing: true)
        context.finishHandshake(session)
        context.transport.emit(.disconnected(session, nil))
        try await waitUntil { finishPicker != nil }
        let finish = try #require(finishPicker)
        context.services.setBluetoothEnabled(false)
        #expect(context.services.isBluetoothEnabled)
        #expect(context.service.isPairingPickerPresented)
        finish()
        finishPicker = nil
        try await waitUntil { !context.service.isPairingPickerPresented }
        #expect(!context.service.isPairingPickerPresented)
        context.services.setBluetoothEnabled(false)
        #expect(!context.services.isBluetoothEnabled)
    }

    @Test("Startup only starts services enabled by the app switches", arguments: [false, true], [false, true])
    func startupRespectsServiceSwitches(bluetoothEnabled: Bool, locationEnabled: Bool) throws {
        let context = try CameraTestContext(
            bluetoothEnabled: bluetoothEnabled,
            locationEnabled: locationEnabled,
            startsLocation: false
        )
        defer { context.cleanup() }

        #expect(context.transport.prepareCount == 0)
        #expect(!context.location.isRunning)

        context.services.startEnabledServices()

        #expect(context.transport.prepareCount == (bluetoothEnabled ? 1 : 0))
        #expect(context.location.isRunning == locationEnabled)
    }
}
