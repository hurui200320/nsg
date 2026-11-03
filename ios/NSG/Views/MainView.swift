//
//  MainView.swift
//  NSG
//

import SwiftUI
import CoreBluetooth
import CoreLocation
import UIKit

struct MainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    let bluetoothService: BluetoothService
    @State private var selectedCameraID: UUID?

    var body: some View {
        List {
            myDeviceSection
            otherDeviceSection
            locationSection
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: bluetoothService.devices.map(\.identifier)
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: bluetoothService.knownCameras.map(\.id)
        )
        .onAppear {
            if !bluetoothService.resumeAutomaticReconnection() {
                bluetoothService.startScan()
            }
        }
        .onDisappear {
            // Leaving the view does not cancel ongoing connections or automatic reconnection.
            if !bluetoothService.isPairing {
                bluetoothService.stopScan(cancelAutoReconnect: false)
            }
        }
        .onChange(of: bluetoothService.connectionState) { _, state in
            if state == .disconnected {
                selectedCameraID = nil
            }
        }
    }

    private var myDeviceSection: some View {
        Section {
            if !bluetoothService.knownCameras.isEmpty {
                ForEach(bluetoothService.knownCameras) { camera in
                    cameraRow(
                        name: camera.name ?? "Unknown camera",
                        isSelected: isCurrentCamera(camera)
                    ) {
                        selectedCameraID = camera.id
                        bluetoothService.connectKnownCamera(camera)
                    }
                }
            }

            if case .pairingNeedsConfirmation = bluetoothService.connectionState {
                Button("Camera shows pairing complete — reconnect") {
                    bluetoothService.confirmPairingOnCamera()
                }
            }

        } header: {
            Text("My camera")
        } footer: {
            switch bluetoothService.connectionState {
            case .failed, .reconnecting, .waitingToReconnect:
                Text(connectionStatus)
                    .accessibilityIdentifier("cameraConnectionStatus")
            default:
                EmptyView()
            }
        }
    }

    private var otherDeviceSection: some View {
        Section {
            if !otherDevices.isEmpty {
                ForEach(otherDevices, id: \.identifier) { device in
                    cameraRow(
                        name: device.name ?? "Unknown camera",
                        isSelected: bluetoothService.activePeripheral?.identifier == device.identifier ||
                            selectedCameraID == device.identifier
                    ) {
                        selectedCameraID = device.identifier
                        bluetoothService.connect(device, firstPairing: true)
                    }
                }
            }

            Button(bluetoothService.isScanning ? "Stop scanning" : "Scan for cameras") {
                if bluetoothService.isScanning {
                    bluetoothService.stopScan()
                } else {
                    bluetoothService.startScan()
                }
            }
            .disabled(!bluetoothService.isScanning && !canStartConnection)
        } header: {
            HStack {
                Text("Other camera")
                if bluetoothService.isScanning {
                    ProgressView()
                }
            }
        }
    }

    private enum CameraRowStatus: String {
        case connected
        case reconnecting
        case disconnected

        var color: Color {
            switch self {
            case .connected: return .green
            case .reconnecting: return .yellow
            case .disconnected: return .red
            }
        }
    }

    private func cameraRowStatus(isSelected: Bool) -> CameraRowStatus {
        guard isSelected, bluetoothService.bluetoothState == .poweredOn else {
            return .disconnected
        }
        switch bluetoothService.connectionState {
        case .ready:
            return .connected
        case .connecting, .discovering, .handshaking, .disconnectingForPairing,
             .showingPairingPicker, .pairingFinished, .pairingNeedsConfirmation,
             .reconnecting, .waitingToReconnect:
            return .reconnecting
        case .disconnected, .disconnecting, .failed:
            return .disconnected
        }
    }

    private func cameraRow(name: String, isSelected: Bool, connect: @escaping () -> Void) -> some View {
        let status = cameraRowStatus(isSelected: isSelected)
        return HStack {
            Button(action: connect) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(status.color)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text(status.rawValue)
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                        .font(.caption)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canStartConnection)

            if status != .disconnected {
                Button(status == .connected ? "disconnected" : "cancel") {
                    bluetoothService.disconnect()
                }
                .buttonStyle(.borderless)
                .contentTransition(.opacity)
                .disabled(bluetoothService.isPairingPickerPresented)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: status)
    }

    private var canStartConnection: Bool {
        bluetoothService.bluetoothState == .poweredOn &&
        bluetoothService.activePeripheral == nil &&
        !bluetoothService.isPairing
    }

    private var otherDevices: [CBPeripheral] {
        let knownIdentifiers = Set(bluetoothService.knownCameras.flatMap {
            [$0.id, $0.peripheralIdentifier]
        })
        return bluetoothService.devices.filter {
            !knownIdentifiers.contains($0.identifier)
        }
    }

    private func isCurrentCamera(_ camera: NikonCameraRecord) -> Bool {
        bluetoothService.activePeripheral?.identifier == camera.peripheralIdentifier ||
        ((selectedCameraID == camera.id ||
          (bluetoothService.isAutomaticReconnectEnabled &&
           bluetoothService.automaticReconnectCameraID == camera.id)) && bluetoothService.isPairing)
    }

    private var bluetoothMessage: String? {
        switch bluetoothService.bluetoothState {
        case .poweredOn: return nil
        case .poweredOff: return "Turn on Bluetooth to connect to your camera."
        case .unauthorized: return "Allow Bluetooth access in Settings to connect to your camera."
        case .unsupported: return "Bluetooth is unavailable on this device."
        case .resetting: return "Bluetooth is restarting…"
        case .unknown: return "Preparing Bluetooth…"
        @unknown default: return "Bluetooth is unavailable."
        }
    }

    private var discoveryMessage: String {
        if let bluetoothMessage { return bluetoothMessage }
        if bluetoothService.isPairing { return "Finish the current connection before pairing another camera." }
        if bluetoothService.activePeripheral != nil { return "Disconnect your camera to search for other cameras." }
        return bluetoothService.isScanning ? "Searching for cameras…" : "No other cameras found. Tap Scan for cameras to search."
    }

    private var connectionStatus: String {
        if let bluetoothMessage { return bluetoothMessage }
        switch bluetoothService.connectionState {
        case .disconnected: return "Select a saved camera to connect, or pair a new camera below."
        case .connecting: return "Connecting to camera…"
        case .discovering, .handshaking: return "Preparing camera…"
        case .ready: return "Connected"
        case .disconnecting: return "Disconnecting…"
        case .disconnectingForPairing: return "Preparing system pairing…"
        case .showingPairingPicker: return "Select your camera in the system window and confirm the codes on both devices."
        case .pairingFinished: return "Pairing finished. Reconnecting to camera…"
        case .pairingNeedsConfirmation:
            return "The system could not confirm pairing. If your camera shows pairing complete, tap the reconnect button above. Otherwise cancel and try pairing again."
        case .reconnecting: return "Searching for your camera to reconnect…"
        case .waitingToReconnect: return "Connection lost. Waiting to retry your last camera… Tap Cancel connection to stop."
        case .failed(let message): return "Connection failed: \(message)"
        }
    }

    private var locationSection: some View {
        Section {
            Toggle("Send location to camera", isOn: Binding(
                get: { bluetoothService.locationService.isRunning },
                set: { enabled in
                    if enabled {
                        bluetoothService.startLocationSync()
                    } else {
                        bluetoothService.stopLocationSync()
                    }
                }
            ))
            .disabled(!bluetoothService.canSendLocation && !bluetoothService.locationService.isRunning)

            if let location = bluetoothService.locationService.latestLocation {
                LabeledContent("Latitude") {
                    Text(location.coordinate.latitude, format: .number.precision(.fractionLength(6)))
                }
                LabeledContent("Longitude") {
                    Text(location.coordinate.longitude, format: .number.precision(.fractionLength(6)))
                }
                if location.horizontalAccuracy >= 0 {
                    LabeledContent("Accuracy") {
                        Text("± \(location.horizontalAccuracy, format: .number.precision(.fractionLength(0))) m")
                    }
                }
                if location.verticalAccuracy >= 0 {
                    LabeledContent("Altitude") {
                        Text("\(location.altitude, format: .number.precision(.fractionLength(0))) m")
                    }
                }
            }

            if let sentAt = bluetoothService.lastLocationSentAt {
                LabeledContent("Last sent") {
                    Text(sentAt, style: .time)
                }
            }

            if bluetoothService.locationService.isRunning {
                Button("Send current location now") {
                    bluetoothService.sendCurrentLocation()
                }
                .disabled(
                    !bluetoothService.canSendLocation ||
                    !bluetoothService.locationService.hasFullAccuracy ||
                    bluetoothService.locationService.latestLocation == nil ||
                    bluetoothService.locationTransferState == .sending
                )
            }

        } header: {
            HStack {
                Text("GPS location")
                if bluetoothService.locationTransferState == .sending {
                    ProgressView()
                }
            }
        }
    }

    private var locationTransferMessage: String {
        if !bluetoothService.canSendLocation {
            return bluetoothService.connectionState == .ready
                ? "GPS sharing is unavailable for this camera connection."
                : "Connect your camera and finish pairing before sending your phone’s location."
        }
        switch bluetoothService.locationTransferState {
        case .idle:
            return "New precise fixes are sent at most once every 10 seconds. Fixes older than 30 seconds or with horizontal error over 20 m are not sent."
        case .sending:
            return "Sending your phone’s current GPS location…"
        case .sent:
            return "The camera acknowledged the GPS write. Check the camera and a new photo to confirm GPS recording."
        case .failed(let message):
            return "GPS was not sent: \(message)"
        }
    }
}

#if DEBUG
#Preview {
    MainView(bluetoothService: BluetoothService())
}
#endif
