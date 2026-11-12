//
//  MainView.swift
//  NSG
//

import SwiftUI
import CoreBluetooth

struct MainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bluetoothService: NikonCameraService
    let isBluetoothEnabled: Bool
    let showsMapPreview: Bool
    @State private var selectedCameraID: UUID?

    var body: some View {
        List {
            myDeviceSection
            locationSection
            otherDeviceSection
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: bluetoothService.devices.map(\.id)
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: bluetoothService.knownCameras.map(\.id)
        )
        .onAppear {
            bluetoothService.setDiscoveryVisible(isBluetoothEnabled)
        }
        .onChange(of: isBluetoothEnabled) { _, isEnabled in
            bluetoothService.setDiscoveryVisible(isEnabled)
        }
        .onDisappear {
            bluetoothService.setDiscoveryVisible(false)
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            bluetoothService.forgetCamera(camera)
                            if selectedCameraID == camera.id {
                                selectedCameraID = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

        } header: {
            Text("My camera")
        } footer: {
            if bluetoothService.knownCameras.isEmpty {
                Text("Your cameras will be listed here.")
            }
        }
//        footer: {
//            switch bluetoothService.connectionState {
//            case .failed, .reconnecting, .waitingToReconnect, .connecting, .discovering, .handshaking,
//                 .disconnectingForPairing, .showingPairingPicker:
//                Text(connectionStatus)
//                    .accessibilityIdentifier("cameraConnectionStatus")
//                if let failure = bluetoothService.lastFailure,
//                   bluetoothService.connectionState == .waitingToReconnect || bluetoothService.connectionState == .reconnecting {
//                    Text(failure.message)
//                }
//            default:
//                EmptyView()
//            }
//        }
    }

    private var otherDeviceSection: some View {
        Section {
            if isBluetoothAvailable, !otherDevices.isEmpty {
                ForEach(otherDevices, id: \.id) { device in
                    cameraRow(
                        name: device.name ?? "Unknown camera",
                        isSelected: bluetoothService.activeDevice?.id == device.id ||
                            selectedCameraID == device.id
                    ) {
                        selectedCameraID = device.id
                        bluetoothService.connect(device, firstPairing: true)
                    }
                }
            }

        } header: {
            HStack {
                Text("Other camera")
                if isBluetoothAvailable && bluetoothService.isNearbyScanningEnabled && bluetoothService.isScanning {
                    ProgressView()
                }
            }
        } footer: {
            if let bluetoothMessage {
                Text(bluetoothMessage)
            } else if !bluetoothService.isNearbyScanningEnabled {
                Text("Nearby scanning is off.")
            } else if otherDevices.isEmpty {
                Text("No other device found.")
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
        guard isSelected, isBluetoothAvailable else {
            return .disconnected
        }
        switch bluetoothService.connectionState {
        case .ready:
            return .connected
        case .connecting, .discovering, .handshaking, .disconnectingForPairing,
             .showingPairingPicker, .reconnecting, .waitingToReconnect:
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
                    Text(name)
                        .foregroundStyle(.primary)

                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)

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

    private var isBluetoothAvailable: Bool {
        isBluetoothEnabled && bluetoothService.bluetoothState == .poweredOn
    }

    private var canStartConnection: Bool {
        isBluetoothAvailable && bluetoothService.canStartConnection
    }

    private var otherDevices: [CameraDevice] {
        let knownIdentifiers = Set(bluetoothService.knownCameras.flatMap {
            [$0.id, $0.peripheralIdentifier]
        })
        return bluetoothService.devices.filter {
            !knownIdentifiers.contains($0.id)
        }
    }

    private func isCurrentCamera(_ camera: NikonCameraRecord) -> Bool {
        bluetoothService.activeDevice?.id == camera.peripheralIdentifier ||
        ((selectedCameraID == camera.id ||
          (bluetoothService.isAutomaticReconnectEnabled &&
           bluetoothService.automaticReconnectCameraID == camera.id)) && bluetoothService.isConnectionOperationInProgress)
    }

    private var bluetoothMessage: String? {
        guard isBluetoothEnabled else {
            return "Bluetooth is off. Turn on Bluetooth to discover nearby cameras."
        }
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
        if bluetoothService.connectionState == .connecting { return "Scanning pauses while connecting to your camera." }
        return bluetoothService.isScanning ? "Searching for cameras…" : "No other cameras found."
    }

    private var connectionStatus: String {
        if let bluetoothMessage { return bluetoothMessage }
        switch bluetoothService.connectionState {
        case .disconnected: return "Select a saved camera to connect, or pair a new camera."
        case .connecting: return "Connecting to camera…"
        case .discovering, .handshaking: return "Preparing camera…"
        case .ready: return "Connected"
        case .disconnecting: return "Disconnecting…"
        case .disconnectingForPairing: return "Preparing system pairing…"
        case .showingPairingPicker: return "Select your camera in the system window and confirm the codes on both devices."
        case .reconnecting: return "Searching for your camera to reconnect…"
        case .waitingToReconnect: return "Connection lost. Waiting to retry your last camera…"
        case .failed(let message): return "Connection failed: \(message)"
        }
    }

    private var locationSection: some View {
        Section("GPS location") {
            GPSLocationCard(
                location: bluetoothService.locationService.latestLocation,
                status: bluetoothService.locationService.status,
                lastSentAt: bluetoothService.lastLocationSentAt,
                transferState: bluetoothService.locationTransferState,
                isLocationRunning: bluetoothService.locationService.isRunning,
                canSendLocation: bluetoothService.canSendLocation &&
                    bluetoothService.locationService.hasFullAccuracy &&
                    bluetoothService.locationService.latestLocation != nil,
                showsMapPreview: showsMapPreview,
                sendLocation: { bluetoothService.sendCurrentLocation() }
            )
        }
    }
}

#if DEBUG
#Preview {
    MainView(bluetoothService: NikonCameraService(), isBluetoothEnabled: true, showsMapPreview: true)
}
#endif
