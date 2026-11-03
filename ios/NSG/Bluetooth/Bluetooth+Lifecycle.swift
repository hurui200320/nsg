//
//  Bluetooth+Lifecycle.swift
//  NSG
//

import Foundation
import CoreBluetooth

extension BluetoothService {
    // MARK: - Timeout and failure handling

    func armTimeout(_ operation: String, seconds: Double = 15) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard let self else { return }
            // Match the device-tested prototype: read PAIR once more without resending Stage 1.
            if self.connectionState == .handshaking,
               self.phase == .waitingStage2, !self.stage2ReadRequested,
               self.pendingWrite == nil, let peripheral = self.activePeripheral,
               peripheral.state == .connected,
               let pair = self.characteristics[self.pairUUID],
               pair.properties.contains(.read) {
                self.stage2ReadRequested = true
                self.armTimeout("Reading Stage 2", seconds: 5)
                peripheral.readValue(for: pair)
                return
            }
            self.fail("\(operation) timed out")
        }
    }

    func fail(_ message: String) {
        stopScan(cancelAutoReconnect: false)
        pairingTarget = nil
        connectingCameraID = nil
        clearHandshake()
        firstPairingRequested = false
        connectionState = .failed(message)
        if let peripheral = activePeripheral {
            central?.cancelPeripheralConnection(peripheral)
        } else {
            scheduleAutomaticReconnection()
        }
    }

    func describe(_ error: Error) -> String {
        let value = error as NSError
        return "\(value.domain) code=\(value.code)：\(value.localizedDescription)"
    }
}
