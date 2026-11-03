//
//  Bluetooth+Handshake.swift
//  NSG
//

import Foundation
import CoreBluetooth

extension BluetoothService {
    // MARK: - Handshake

    func startHandshake() throws {
        guard let peripheral = activePeripheral,
              let pair = characteristics[pairUUID],
              pair.properties.contains(.write),
              pair.properties.contains(.indicate),
              !pair.properties.contains(.notify),
              let not1 = characteristics[not1UUID],
              not1.properties.contains(.notify),
              let id = characteristics[idUUID],
              id.properties.contains(.write) else {
            throw ServiceError.invalidCharacteristics
        }

        // Use only the prototype-validated scan connection path, reusing the original identity storage keys and migration logic.
        let resolution = try NikonProbeIdentityStore(defaults: defaults).resolve(
            identifier: peripheral.identifier,
            name: peripheral.name,
            systemConnected: false
        )
        stage1 = NikonPairingProtocol.makeStage1(
            device: resolution.identity.device,
            nonce: resolution.identity.nonce
        )
        connectionState = .handshaking
        phase = .subscribingPair
        armTimeout("Subscribing to PAIR")
        subscribe(pairUUID)
    }

    private func subscribe(_ uuid: CBUUID) {
        guard let peripheral = activePeripheral,
              let characteristic = characteristics[uuid] else {
            fail("Subscription characteristic not found")
            return
        }
        if characteristic.isNotifying {
            advanceSubscription(uuid)
        } else {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func advanceSubscription(_ uuid: CBUUID) {
        if phase == .subscribingPair, uuid == pairUUID {
            phase = .subscribingNot1
            armTimeout("Subscribing to NOT1")
            subscribe(not1UUID)
        } else if phase == .subscribingNot1, uuid == not1UUID {
            guard let stage1 else {
                fail("Missing Stage 1 message")
                return
            }
            phase = .waitingStage2
            armTimeout("Waiting for Stage 2")
            enqueue(stage1.data, uuid: pairUUID, purpose: .stage1)
        }
    }

    func writeControllerName() {
        guard connectionState == .handshaking, phase == .waitingSuccess else { return }
        successWaitTask?.cancel()
        phase = .writingName
        // Preserve the device-tested 32-byte ASCII name and zero-padding behavior.
        var data = Data("NSG-iOS-Probe".utf8)
        data.append(Data(repeating: 0, count: 32 - data.count))
        armTimeout("Writing controller name")
        enqueue(data, uuid: idUUID, purpose: .name)
    }

    func enqueue(_ data: Data, uuid: CBUUID, purpose: WritePurpose) {
        writeQueue.append((data, uuid, purpose))
        drainWrites()
    }

    func drainWrites() {
        guard connectionState == .handshaking, pendingWrite == nil,
              !writeQueue.isEmpty, let peripheral = activePeripheral,
              peripheral.state == .connected else { return }
        let (data, uuid, purpose) = writeQueue.removeFirst()
        guard let characteristic = characteristics[uuid],
              characteristic.properties.contains(.write),
              data.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
            fail("Characteristic is not writable or data exceeds the length limit")
            return
        }
        // Camera indications may arrive before write acknowledgements; manage the write queue separately from the protocol stage.
        pendingWrite = purpose
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func handshakeCompleted() {
        clearHandshake()
        guard firstPairingRequested else {
            connectionState = .ready
            recordSuccessfulConnection()
            return
        }
        guard let peripheral = activePeripheral else {
            fail("The current connection was lost")
            return
        }
        guard rememberPairingTarget(peripheral) else { return }
        connectionState = .disconnectingForPairing
        armTimeout("Releasing GATT connection", seconds: 10)
        central?.cancelPeripheralConnection(peripheral)
    }

    func clearHandshake() {
        resetLocationTransfer()
        timeoutTask?.cancel()
        timeoutTask = nil
        successWaitTask?.cancel()
        successWaitTask = nil
        phase = .idle
        stage1 = nil
        successSeen = false
        stage2ReadRequested = false
        pendingWrite = nil
        writeQueue.removeAll()
    }

    private enum ServiceError: LocalizedError {
        case invalidCharacteristics

        var errorDescription: String? {
            "PAIR, NOT1, or ID characteristic is missing or has incompatible properties"
        }
    }
}

// MARK: - Handshake callbacks

extension BluetoothService {
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === activePeripheral, connectionState == .handshaking,
              characteristic.uuid == pairUUID || characteristic.uuid == not1UUID else { return }
        if let error {
            fail(describe(error))
            return
        }
        guard characteristic.isNotifying else {
            fail("Handshake subscription is not enabled or has been disabled")
            return
        }
        advanceSubscription(characteristic.uuid)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === activePeripheral, connectionState == .handshaking,
              characteristic.uuid == pairUUID || characteristic.uuid == not1UUID else { return }
        if let error {
            fail(describe(error))
            return
        }
        guard let data = characteristic.value else { return }
        if characteristic.uuid == not1UUID {
            if data == Data([0x01, 0x00]) {
                successSeen = true
                if phase == .waitingSuccess { writeControllerName() }
            }
            return
        }
        guard phase == .waitingStage2 || phase == .waitingStage4 else { return }
        do {
            let message = try NikonPairingMessage(data: data)
            if phase == .waitingStage2, message.stage == 2, let stage1 {
                let response = try NikonPairingProtocol.response(to: message, stage1: stage1)
                phase = .waitingStage4
                armTimeout("Waiting for Stage 4")
                enqueue(response.message.data, uuid: pairUUID, purpose: .stage3)
            } else if phase == .waitingStage4, message.stage == 4 {
                phase = .waitingSuccess
                armTimeout("Completing handshake")
                if successSeen {
                    writeControllerName()
                } else {
                    // Preserve device-tested behavior: some cameras send NOT1 only after the ID write.
                    successWaitTask?.cancel()
                    successWaitTask = Task { @MainActor [weak self] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                        } catch {
                            return
                        }
                        self?.writeControllerName()
                    }
                }
            }
        } catch {
            fail(describe(error))
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if characteristic.uuid == geoUUID {
            handleGeoWriteResponse(peripheral, error: error)
            return
        }
        guard peripheral === activePeripheral, connectionState == .handshaking,
              let purpose = pendingWrite else { return }
        let expectedUUID: CBUUID
        switch purpose {
        case .stage1, .stage3: expectedUUID = pairUUID
        case .name: expectedUUID = idUUID
        case .geo: return
        }
        guard characteristic.uuid == expectedUUID else { return }
        pendingWrite = nil
        if let error {
            fail(describe(error))
            return
        }
        switch purpose {
        case .name: handshakeCompleted()
        case .stage1, .stage3: drainWrites()
        case .geo: return
        }
    }
}
