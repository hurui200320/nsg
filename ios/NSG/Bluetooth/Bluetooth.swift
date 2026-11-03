//
//  Bluetooth.swift
//  NSG
//

import Foundation
import CoreBluetooth
import CoreLocation
import Observation

@MainActor
@Observable
final class BluetoothService: NSObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case discovering
        case handshaking
        case ready
        case disconnecting
        case disconnectingForPairing
        case showingPairingPicker
        /// The system pairing dialog completed successfully; automatically transition to reconnecting.
        case pairingFinished
        /// The system picker could not confirm the result; wait for the user to verify the camera's status.
        case pairingNeedsConfirmation(String)
        case reconnecting
        case waitingToReconnect
        case failed(String)
    }

    // MARK: - Internal protocol state

    enum HandshakePhase {
        case idle
        case subscribingPair
        case subscribingNot1
        case waitingStage2
        case waitingStage4
        case waitingSuccess
        case writingName
    }

    enum WritePurpose {
        case stage1
        case stage3
        case name
        case geo
    }

    // MARK: - Observable state
    // Writable within the module so feature extensions in other files can update it.

    var bluetoothState: CBManagerState = .unknown
    var devices: [CBPeripheral] = []
    var knownCameras: [NikonCameraRecord] = []
    var automaticReconnectCameraID: UUID?
    var isAutomaticReconnectEnabled = false
    var isScanning = false
    var connectionState: ConnectionState = .disconnected
    var activePeripheral: CBPeripheral?
    var isPairingPickerPresented = false
    let locationService = LocationService()
    var locationTransferState: LocationTransferState = .idle
    var lastSentLocation: CLLocation?
    var lastLocationSentAt: Date?

    var canScan: Bool {
        bluetoothState == .poweredOn && activePeripheral == nil && (!isPairing || connectionState == .reconnecting)
    }

    /// Includes the handshake phase of normal connections to prevent duplicate connections or scans during an operation.
    var isPairing: Bool {
        if isPairingPickerPresented { return true }
        switch connectionState {
        case .connecting, .discovering, .handshaking,
             .disconnecting, .disconnectingForPairing, .showingPairingPicker, .reconnecting,
             .pairingNeedsConfirmation, .waitingToReconnect:
            return true
        default:
            return false
        }
    }

    // MARK: - Nikon characteristic UUIDs

    let nikonService = CBUUID(string: "0000DE00-3DD4-4255-8D62-6DC7B9BD5561")
    let pairUUID = CBUUID(string: "00002000-3DD4-4255-8D62-6DC7B9BD5561")
    let not1UUID = CBUUID(string: "00002008-3DD4-4255-8D62-6DC7B9BD5561")
    let geoUUID = CBUUID(string: "00002007-3DD4-4255-8D62-6DC7B9BD5561")
    let idUUID = CBUUID(string: "00002002-3DD4-4255-8D62-6DC7B9BD5561")

    // MARK: - Shared implementation state

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored var pairingTarget: NikonCameraRecord?
    @ObservationIgnored var reconnectionTarget: NikonCameraRecord?
    @ObservationIgnored var connectingCameraID: UUID?
    @ObservationIgnored var automaticReconnectTask: Task<Void, Never>?
    @ObservationIgnored var automaticReconnectTaskID: UUID?
    @ObservationIgnored var automaticReconnectAttemptCount = 0
    @ObservationIgnored var reconnectionTask: Task<Void, Never>?

    override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
        knownCameras = NikonCameraStore(defaults: defaults).load()
        let preference = NikonAutoReconnectStore(defaults: defaults).load(knownCameras: knownCameras)
        automaticReconnectCameraID = preference.cameraID
        isAutomaticReconnectEnabled = preference.isEnabled
        persistAutomaticReconnectPreference()
    }

    @ObservationIgnored var central: CBCentralManager?
    @ObservationIgnored var scanRequested = false
    @ObservationIgnored var characteristics: [CBUUID: CBCharacteristic] = [:]
    @ObservationIgnored var firstPairingRequested = false
    @ObservationIgnored var phase: HandshakePhase = .idle
    @ObservationIgnored var stage1: NikonPairingMessage?
    @ObservationIgnored var successSeen = false
    @ObservationIgnored var stage2ReadRequested = false
    @ObservationIgnored var writeQueue: [(Data, CBUUID, WritePurpose)] = []
    @ObservationIgnored var pendingWrite: WritePurpose?
    @ObservationIgnored var timeoutTask: Task<Void, Never>?
    @ObservationIgnored var successWaitTask: Task<Void, Never>?
    @ObservationIgnored var geoWriteTask: Task<Void, Never>?
    @ObservationIgnored var pendingGeoLocation: CLLocation?
    @ObservationIgnored var geoWriteID: UUID?
    @ObservationIgnored var pickerTask: Task<Void, Never>?
}
