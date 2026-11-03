//
//  Bluetooth+Pairing.swift
//  NSG
//

import Foundation
import CoreBluetooth

extension BluetoothService {
    // MARK: - System pairing dialog

    func showPairingPicker() {
        connectionState = .showingPairingPicker
        isPairingPickerPresented = true
        pickerTask = Task { @MainActor [weak self] in
            let outcome = await NikonAccessoryPicker.present()
            guard let self else { return }
            self.isPairingPickerPresented = false
            self.pickerTask = nil
            // Preserve the failure state if Bluetooth becomes unavailable; wait for the system dialog to return before allowing new operations.
            guard self.connectionState == .showingPairingPicker else { return }
            self.handlePairingOutcome(outcome)
        }
    }

    func handlePairingOutcome(_ outcome: NikonAccessoryPicker.Outcome) {
        firstPairingRequested = false
        switch outcome {
        case .completed, .alreadyConnected:
            finishPairingAndReconnect()
        case .notFound(let detail):
            // resultNotFound does not determine the camera-side outcome. Keep the target and wait for user confirmation;
            // do not save to the known camera list or automatically reopen the system dialog yet.
            guard pairingTarget != nil else {
                fail("No pairing camera found for confirmation")
                return
            }
            connectionState = .pairingNeedsConfirmation(detail)
        case .cancelled:
            pairingTarget = nil
            connectionState = .disconnected
        case .failed(let detail):
            pairingTarget = nil
            connectionState = .failed(detail)
        case .simulatorUnavailable:
            pairingTarget = nil
            connectionState = .failed("Use a physical iPhone")
        }
    }

    /// Save the target and reconnect only after the user confirms that the camera shows pairing success.
    func confirmPairingOnCamera() {
        guard case .pairingNeedsConfirmation = connectionState,
              !isPairingPickerPresented else { return }
        finishPairingAndReconnect()
    }
}
