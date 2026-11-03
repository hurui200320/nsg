import Foundation
import CoreBluetooth

extension BluetoothService {
    /// Call when the user selects a known camera. Also restore automatic reconnection for that camera.
    func connectKnownCamera(_ camera: NikonCameraRecord) {
        guard activePeripheral == nil, !isPairing,
              let saved = knownCameras.first(where: { $0.id == camera.id }) else { return }
        enableAutomaticReconnection(for: saved.id)
        startTargetReconnection(saved)
    }

    func startTargetReconnection(_ target: NikonCameraRecord) {
        guard activePeripheral == nil, !isPairingPickerPresented else { return }
        stopScan(cancelAutoReconnect: false)
        guard central == nil || central?.state == .poweredOn ||
                central?.state == .unknown || central?.state == .resetting else {
            fail("Bluetooth is unavailable; cannot reconnect to the camera")
            return
        }
        reconnectionTarget = target
        connectionState = .reconnecting
        scanRequested = true
        devices.removeAll()
        prepare()
        beginScanIfReady()
        reconnectionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            guard let self, self.reconnectionTarget?.id == target.id else { return }
            self.fail("Target camera rediscovery timed out. Make sure the camera is on and this phone is selected.")
        }
    }

    func cancelTargetReconnection() {
        reconnectionTask?.cancel()
        reconnectionTask = nil
        reconnectionTarget = nil
        if connectionState == .reconnecting {
            connectionState = .disconnected
        }
    }

    func reconnectIfMatched(_ peripheral: CBPeripheral, advertisementData: [String: Any]) {
        guard let target = reconnectionTarget,
              NikonCameraMatcher.matches(
                target,
                identifier: peripheral.identifier,
                manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                knownCameras: knownCameras
              ) else { return }

        // Explicitly associate the original identity when the UUID changes so startHandshake does not create a new controller identity.
        NikonProbeIdentityStore(defaults: defaults).associate(
            target.identity, identifier: peripheral.identifier, name: peripheral.name
        )
        stopScan(cancelAutoReconnect: false)
        connect(peripheral, isAutomatic: true)
        if activePeripheral === peripheral {
            connectingCameraID = target.id
        }
    }

    /// Remove from the local list without deleting the camera/iOS system pairing relationship or handshake identity.
    func forgetCamera(_ camera: NikonCameraRecord) {
        if automaticReconnectCameraID == camera.id {
            disableAutomaticReconnection()
        }
        if reconnectionTarget?.id == camera.id {
            stopScan(cancelAutoReconnect: false)
        }
        var updated = knownCameras
        updated.removeAll { $0.id == camera.id }
        persistCameras(updated)
    }

    @discardableResult
    func persistCameras(_ cameras: [NikonCameraRecord]) -> Bool {
        do {
            try NikonCameraStore(defaults: defaults).save(cameras)
            knownCameras = cameras
            return true
        } catch {
            fail("Failed to save camera record: \(describe(error))")
            return false
        }
    }

    func rememberPairingTarget(_ peripheral: CBPeripheral) -> Bool {
        guard let identity = NikonProbeIdentityStore(defaults: defaults).existingIdentity(
            identifier: peripheral.identifier, name: peripheral.name
        ) else {
            fail("Handshake identity for the target camera not found")
            return false
        }
        let existing = knownCameras.first { $0.peripheralIdentifier == peripheral.identifier }
        pairingTarget = NikonCameraRecord(
            id: existing?.id ?? peripheral.identifier,
            peripheralIdentifier: peripheral.identifier,
            name: peripheral.name,
            controllerDevice: identity.device,
            controllerNonce: identity.nonce,
            pairingCompletedAt: Date(),
            lastConnectedAt: existing?.lastConnectedAt
        )
        return true
    }

    func finishPairingAndReconnect() {
        guard var target = pairingTarget else {
            fail("Target camera information was lost when system pairing returned")
            return
        }
        pairingTarget = nil
        target.pairingCompletedAt = Date()
        var updated = knownCameras
        updated.removeAll { $0.id == target.id }
        updated.append(target)
        guard persistCameras(updated) else { return }
        enableAutomaticReconnection(for: target.id)
        connectionState = .pairingFinished
        startTargetReconnection(target)
    }

    func recordSuccessfulConnection() {
        defer { connectingCameraID = nil }
        guard let peripheral = activePeripheral,
              let index = knownCameras.firstIndex(where: {
                  $0.id == connectingCameraID || $0.peripheralIdentifier == peripheral.identifier
              }) else { return }
        var updated = knownCameras
        updated[index].peripheralIdentifier = peripheral.identifier
        updated[index].name = peripheral.name ?? updated[index].name
        updated[index].lastConnectedAt = Date()
        if persistCameras(updated) {
            enableAutomaticReconnection(for: updated[index].id)
        }
    }
}
