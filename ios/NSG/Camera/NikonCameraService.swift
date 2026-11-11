import Foundation
import CoreBluetooth
import CoreLocation
import Observation

/// Entry point for UI camera operations and state; coordinates transport, handshake, persistence, and GPS sync.
@MainActor
@Observable
final class NikonCameraService {
    /// UI connection state. Only ready means the Nikon handshake is complete; BLE connection alone is
    /// insufficient.
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case discovering
        case handshaking
        case ready
        case disconnecting
        case disconnectingForPairing
        case showingPairingPicker
        case reconnecting
        case waitingToReconnect
        case failed(String)
    }

    /// Application policy installed by AppServiceController; checked at every Bluetooth entry point.
    @ObservationIgnored var isBluetoothAllowed: () -> Bool = { true }
    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var devices: [CameraDevice] = []
    private(set) var knownCameras: [NikonCameraRecord]
    /// Stable record ID of the automatic reconnect target, separate from its potentially changing peripheral
    /// UUID.
    private(set) var automaticReconnectCameraID: UUID?
    private(set) var isAutomaticReconnectEnabled: Bool
    private(set) var isScanning = false
    private(set) var isNearbyScanningEnabled = true
    private(set) var connectionState: ConnectionState = .disconnected {
        didSet { resumeVisibleDiscovery() }
    }
    private(set) var activeDevice: CameraDevice?
    private(set) var isPairingPickerPresented = false
    /// Most recent failure, retained during retry waits for UI feedback and diagnostics.
    private(set) var lastFailure: CameraFailure?
    let locationSync: LocationSyncCoordinator

    var locationService: any LocationProviding { locationSync.source }
    var locationTransferState: LocationTransferState { locationSync.transferState }
    var lastSentLocation: CLLocation? { locationSync.lastSentLocation }
    var lastLocationSentAt: Date? { locationSync.lastSentAt }
    /// Requires app permission to use both services, active acquisition, and a GEO-capable camera session.
    var canSendLocation: Bool {
        isBluetoothAllowed() && locationSync.isLocationAllowed() && locationService.isRunning &&
        connectionState == .ready && capabilities?.supportsLocation == true
    }

    /// Used by the UI to block new connections, including during disconnect, system pairing, and retry waits.
    var isConnectionOperationInProgress: Bool {
        if isPairingPickerPresented { return true }
        return switch connectionState {
        case .connecting, .discovering, .handshaking, .disconnecting, .disconnectingForPairing,
             .showingPairingPicker, .reconnecting, .waitingToReconnect: true
        default: false
        }
    }

    var canStartConnection: Bool {
        isBluetoothAllowed() && bluetoothState == .poweredOn && activeDevice == nil && !isConnectionOperationInProgress
    }

    /// Check before resuming or scheduling retries; excludes cancellation, missing targets, and errors
    /// requiring user action.
    var shouldAutomaticallyReconnect: Bool {
        guard isBluetoothAllowed(), isAutomaticReconnectEnabled, let cameraID = automaticReconnectCameraID,
              knownCameras.contains(where: { $0.id == cameraID }),
              bluetoothState == .poweredOn, activeDevice == nil,
              !isPairingPickerPresented, pairingTarget == nil,
              lastFailure?.recovery != .userAction else { return false }
        return switch connectionState {
        case .disconnected, .failed, .waitingToReconnect: true
        default: false
        }
    }

    /// Communication interface: Bluetooth in production, replaceable with a fake transport in tests.
    @ObservationIgnored private let transport: any CameraTransport
    @ObservationIgnored private let repository: CameraRepository
    @ObservationIgnored private let scheduler: any CameraScheduling
    @ObservationIgnored private let presentPicker: @MainActor () async -> NikonAccessoryPicker.Outcome
    @ObservationIgnored private let makeStage1: @MainActor (NikonControllerIdentity) -> NikonPairingMessage
    /// Created by beginConnection for each attempt; used to discard callbacks belonging to older sessions.
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var capabilities: CameraCapabilities?
    @ObservationIgnored private var handshake = NikonHandshake()
    @ObservationIgnored private var currentIdentity: NikonControllerIdentity?
    @ObservationIgnored private var connectingCameraID: UUID?
    /// Whether this handshake must be followed by BLE disconnection and the system pairing picker.
    @ObservationIgnored private var firstPairingRequested = false
    /// Temporary target retained while the system pairing picker is open.
    @ObservationIgnored private var pairingTarget: NikonCameraRecord?
    @ObservationIgnored private var reconnectionTarget: NikonCameraRecord?
    @ObservationIgnored private var operationTimer: CameraTimer?
    @ObservationIgnored private var nameTimer: CameraTimer?
    @ObservationIgnored private var retryTimer: CameraTimer?
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var pickerTask: Task<Void, Never>?
    @ObservationIgnored private var isDiscoveryVisible = false

    /// Loads saved state and binds callbacks without starting Bluetooth or location; dependencies are
    /// injectable for tests.
    init(defaults: UserDefaults = .standard,
         transport: (any CameraTransport)? = nil,
         scheduler: (any CameraScheduling)? = nil,
         locationSource: (any LocationProviding)? = nil,
         presentPicker: @escaping @MainActor () async -> NikonAccessoryPicker.Outcome = { await NikonAccessoryPicker.present() },
         makeStage1: @escaping @MainActor (NikonControllerIdentity) -> NikonPairingMessage = {
             NikonPairingProtocol.makeStage1(device: $0.device, nonce: $0.nonce)
         }) {
        self.transport = transport ?? BluetoothTransport()
        self.repository = CameraRepository(defaults: defaults)
        self.scheduler = scheduler ?? SystemCameraScheduler()
        self.presentPicker = presentPicker
        self.makeStage1 = makeStage1
        let cameras = repository.loadCameras()
        knownCameras = cameras
        let preference = repository.loadReconnectPreference(cameras: cameras)
        automaticReconnectCameraID = preference.cameraID
        isAutomaticReconnectEnabled = preference.isEnabled
        repository.saveReconnectPreference(preference)
        locationSync = LocationSyncCoordinator(source: locationSource ?? LocationService(), scheduler: self.scheduler)
        self.transport.onEvent = { [weak self] event in self?.handle(event) }
        locationSync.isAvailable = { [weak self] in self?.canSendLocation == true }
        locationSync.submit = { [weak self] data in
            guard let self, let sessionID = self.sessionID else { return }
            self.transport.write(data, to: .location, sessionID: sessionID)
        }
        locationSync.onConnectionFailure = { [weak self] error in self?.fail(error) }
    }

    /// Starts app Bluetooth use and resumes eligible discovery/reconnection; system availability arrives asynchronously.
    func prepare() {
        guard isBluetoothAllowed() else { return }
        transport.prepare()
        resumeAutomaticReconnection()
        resumeVisibleDiscovery()
    }

    /// Called by the app controller on shutdown; cancels discovery, connection, and automatic reconnection.
    func stopBluetooth() {
        guard !isPairingPickerPresented else { return }
        isDiscoveryVisible = false
        disconnect()
    }

    /// Called when scenePhase changes to update foreground/background scan filtering.
    func setForeground(_ isForeground: Bool) { transport.setForeground(isForeground) }
    func sendCurrentLocation() { locationSync.sendCurrentLocation() }

    /// Keeps discovery active while the camera list is visible, including after a BLE connection succeeds.
    func setDiscoveryVisible(_ isVisible: Bool) {
        isDiscoveryVisible = isVisible
        if isVisible, isBluetoothAllowed() {
            transport.prepare()
            resumeAutomaticReconnection()
            resumeVisibleDiscovery()
        } else {
            pauseDiscovery()
        }
    }

    /// Changes general discovery without cancelling a connection or saved-camera rediscovery deadline.
    func setNearbyScanningEnabled(_ enabled: Bool) {
        guard isNearbyScanningEnabled != enabled else { return }
        isNearbyScanningEnabled = enabled
        if !enabled { devices.removeAll() }
        if reconnectionTarget != nil, isBluetoothAllowed() {
            transport.startScan(mode: enabled && isDiscoveryVisible ? .discovery : .reconnection)
        } else if enabled {
            resumeVisibleDiscovery()
        } else {
            transport.stopScan()
        }
    }

    private func resumeVisibleDiscovery() {
        guard isBluetoothAllowed(), isNearbyScanningEnabled, isDiscoveryVisible, bluetoothState == .poweredOn,
              connectionState != .connecting, !isScanning else { return }
        transport.startScan(mode: .discovery)
    }

    /// Called to discover new cameras; clears previous results and ignores requests while a connection flow is
    /// busy.
    func startScan() {
        guard isBluetoothAllowed(), isNearbyScanningEnabled, activeDevice == nil,
              !isConnectionOperationInProgress, !isScanning else { return }
        guard bluetoothState == .poweredOn || bluetoothState == .unknown || bluetoothState == .resetting else { return }
        lastFailure = nil
        devices.removeAll()
        transport.startScan(mode: .discovery)
    }

    /// Called when the view leaves; pauses idle discovery without changing reconnect preferences or
    /// interrupting connection flows.
    func pauseDiscovery() {
        guard !isConnectionOperationInProgress else { return }
        stopScanning()
    }

    /// Called when the user stops scanning; also persistently disables reconnection if target discovery or a
    /// retry is pending.
    func stopScan() {
        let wasReconnecting = reconnectionTarget != nil || retryTimer != nil
        stopScanning()
        if wasReconnecting {
            disableAutomaticReconnection()
            connectionState = .disconnected
        }
    }

    /// Called when the user selects a scan result; firstPairing requires system pairing after the BLE
    /// handshake.
    func connect(_ device: CameraDevice, firstPairing: Bool = false) {
        guard canStartConnection else { return }
        lastFailure = nil
        let camera = knownCameras.first { $0.peripheralIdentifier == device.id }
        if let camera, !firstPairing {
            enableAutomaticReconnection(for: camera.id)
        } else {
            disableAutomaticReconnection()
        }
        beginConnection(device, camera: camera, firstPairing: firstPairing)
    }

    /// Called when the user selects a saved camera; enables reconnection and rediscovers its current peripheral
    /// identity.
    func connectKnownCamera(_ camera: NikonCameraRecord) {
        guard isBluetoothAllowed(), activeDevice == nil, !isConnectionOperationInProgress,
              let saved = knownCameras.first(where: { $0.id == camera.id }) else { return }
        lastFailure = nil
        enableAutomaticReconnection(for: saved.id)
        startTargetReconnection(saved)
    }

    /// Called for user cancellation or Bluetooth shutdown; disables reconnection and waits for the disconnect
    /// callback.
    /// Ignored while the system pairing picker is open; the user must complete or cancel that picker first.
    func disconnect() {
        guard !isPairingPickerPresented else { return }
        disableAutomaticReconnection()
        stopScanning()
        pairingTarget = nil
        firstPairingRequested = false
        cancelOperation()
        handshake.reset()
        locationSync.connectionEnded()
        guard let sessionID else {
            connectionState = .disconnected
            return
        }
        connectionState = .disconnecting
        transport.disconnect(sessionID: sessionID)
    }

    /// Removes the local camera record without removing the system bond or stored controller identity.
    func forgetCamera(_ camera: NikonCameraRecord) {
        if automaticReconnectCameraID == camera.id { disableAutomaticReconnection() }
        if reconnectionTarget?.id == camera.id {
            stopScanning()
            connectionState = .disconnected
        }
        persistCameras(knownCameras.filter { $0.id != camera.id })
    }

    /// Called on Bluetooth recovery or foreground entry; true means target scanning started or a retry is
    /// pending.
    @discardableResult
    func resumeAutomaticReconnection() -> Bool {
        guard shouldAutomaticallyReconnect else { return false }
        guard retryTimer == nil else { return true }
        guard let target = knownCameras.first(where: { $0.id == automaticReconnectCameraID }) else { return false }
        startTargetReconnection(target)
        return true
    }

    /// Saves the pairing target and reconnects to verify it through the Nikon handshake.
    private func finishPairingAndReconnect() {
        guard var target = pairingTarget else {
            fail(CameraFailure("The pairing target was lost.", recovery: .userAction))
            return
        }
        target.pairingCompletedAt = scheduler.now
        guard persistCameras(knownCameras.filter { $0.id != target.id } + [target]) else { return }
        pairingTarget = nil
        lastFailure = nil
        enableAutomaticReconnection(for: target.id)
        startTargetReconnection(target)
    }

    /// Called for a selected scan result or matched saved target; prepares identity, session, and timeout
    /// before connecting.
    private func beginConnection(_ device: CameraDevice, camera: NikonCameraRecord?, firstPairing: Bool) {
        stopScanning()
        cancelOperation()
        handshake.reset()
        locationSync.resetForConnection()
        capabilities = nil
        currentIdentity = repository.identity(for: device, camera: camera, knownCameras: knownCameras)
        connectingCameraID = camera?.id
        firstPairingRequested = firstPairing
        pairingTarget = nil
        activeDevice = device
        let token = UUID()
        sessionID = token
        connectionState = .connecting
        armTimeout("Connecting to camera")
        transport.connect(device, sessionID: token)
    }

    /// Shared entry for manual and automatic reconnection; scans for the target within a deadline before
    /// connecting.
    private func startTargetReconnection(_ target: NikonCameraRecord) {
        stopScanning()
        guard bluetoothState == .poweredOn || bluetoothState == .unknown || bluetoothState == .resetting else {
            fail(CameraFailure("Bluetooth is unavailable; cannot reconnect to the camera."))
            return
        }
        reconnectionTarget = target
        connectionState = .reconnecting
        devices.removeAll()
        armTimeout("Target camera rediscovery", seconds: ReconnectPolicy.rediscoveryTimeout)
        transport.startScan(mode: isNearbyScanningEnabled && isDiscoveryVisible ? .discovery : .reconnection)
    }

    /// Stops scanning and target discovery timing during internal transitions without changing reconnect
    /// preferences.
    private func stopScanning() {
        if reconnectionTarget != nil { operationTimer?.cancel(); operationTimer = nil }
        reconnectionTarget = nil
        transport.stopScan()
    }

    private func enableAutomaticReconnection(for cameraID: UUID) {
        cancelRetry()
        automaticReconnectCameraID = cameraID
        isAutomaticReconnectEnabled = true
        retryAttempt = 0
        persistReconnectPreference()
    }

    /// Persists disabled reconnection after user cancellation or target changes; not for ordinary connection
    /// failures.
    private func disableAutomaticReconnection() {
        cancelRetry()
        isAutomaticReconnectEnabled = false
        retryAttempt = 0
        persistReconnectPreference()
    }

    private func persistReconnectPreference() {
        repository.saveReconnectPreference(NikonAutoReconnectPreference(
            cameraID: automaticReconnectCameraID, isEnabled: isAutomaticReconnectEnabled
        ))
    }

    /// Schedules a backoff retry after failure once no connection is active; does not duplicate an existing
    /// retry timer.
    private func scheduleAutomaticReconnection() {
        guard shouldAutomaticallyReconnect, retryTimer == nil else { return }
        retryAttempt = min(retryAttempt + 1, 6)
        connectionState = .waitingToReconnect
        retryTimer = scheduler.schedule(after: ReconnectPolicy.delay(attempt: retryAttempt)) { [weak self] in
            guard let self else { return }
            self.retryTimer = nil
            self.resumeAutomaticReconnection()
        }
    }

    private func cancelRetry() {
        retryTimer?.cancel()
        retryTimer = nil
        if connectionState == .waitingToReconnect { connectionState = .disconnected }
    }

    /// Resets the deadline for each connection or handshake phase; permits one eligible Stage 2 recovery read
    /// before failing.
    private func armTimeout(_ operation: String, seconds: TimeInterval = 15) {
        operationTimer?.cancel()
        operationTimer = scheduler.schedule(after: seconds) { [weak self] in
            guard let self else { return }
            if self.connectionState == .handshaking,
               let effects = self.handshake.recoverStage2Timeout(
                   canReadPair: self.capabilities?.properties[.pairing]?.contains(.read) == true
               ) {
                self.perform(effects)
            } else {
                self.fail(CameraFailure("\(operation) timed out."))
            }
        }
    }

    private func cancelOperation() {
        operationTimer?.cancel()
        operationTimer = nil
        nameTimer?.cancel()
        nameTimer = nil
    }

    /// Handles failure or timeout while preserving its cause; waits for disconnection, or evaluates retries
    /// immediately if idle.
    private func fail(_ failure: CameraFailure) {
        lastFailure = failure
        stopScanning()
        cancelOperation()
        handshake.reset()
        locationSync.connectionEnded()
        pairingTarget = nil
        firstPairingRequested = false
        connectionState = .failed(failure.message)
        if let sessionID {
            transport.disconnect(sessionID: sessionID)
        } else {
            scheduleAutomaticReconnection()
        }
    }

    @discardableResult
    private func persistCameras(_ cameras: [NikonCameraRecord]) -> Bool {
        do {
            try repository.saveCameras(cameras)
            knownCameras = cameras
            return true
        } catch {
            fail(CameraFailure("Failed to save camera record: \(error.localizedDescription)", recovery: .userAction))
            return false
        }
    }

    /// Executes handshake effects in order, delegating Bluetooth I/O and timing to the corresponding
    /// dependencies.
    private func perform(_ effects: [NikonHandshake.Effect]) {
        guard let sessionID else { return }
        for effect in effects {
            switch effect {
            case .subscribe(let characteristic):
                transport.subscribe(characteristic, sessionID: sessionID)
            case .write(let characteristic, let data):
                transport.write(data, to: characteristic, sessionID: sessionID)
            case .readPair:
                transport.read(.pairing, sessionID: sessionID)
            case .timeout(let operation, let seconds):
                armTimeout(operation, seconds: seconds)
            case .deferNameWrite:
                nameTimer?.cancel()
                nameTimer = scheduler.schedule(after: 3) { [weak self] in
                    guard let self, self.connectionState == .handshaking else { return }
                    self.perform(self.handshake.writeName())
                }
            case .completed:
                completeHandshake()
            }
        }
    }

    /// Called after the name write is acknowledged; enters ready, or disconnects BLE for initial system
    /// pairing.
    private func completeHandshake() {
        cancelOperation()
        if firstPairingRequested {
            guard let device = activeDevice, let identity = currentIdentity else {
                fail(CameraFailure("The pairing target was lost.", recovery: .userAction))
                return
            }
            let existing = knownCameras.first { $0.peripheralIdentifier == device.id }
            pairingTarget = NikonCameraRecord(
                id: existing?.id ?? device.id, peripheralIdentifier: device.id, name: device.name,
                controllerDevice: identity.device, controllerNonce: identity.nonce,
                pairingCompletedAt: scheduler.now, lastConnectedAt: existing?.lastConnectedAt
            )
            connectionState = .disconnectingForPairing
            armTimeout("Releasing GATT connection", seconds: 10)
            if let sessionID { transport.disconnect(sessionID: sessionID) }
            return
        }
        connectionState = .ready
        lastFailure = nil
        locationSync.connectionReady()
        guard let device = activeDevice,
              let index = knownCameras.firstIndex(where: {
                  $0.id == connectingCameraID || $0.peripheralIdentifier == device.id
              }) else { return }
        var cameras = knownCameras
        cameras[index].peripheralIdentifier = device.id
        cameras[index].name = device.name ?? cameras[index].name
        cameras[index].lastConnectedAt = scheduler.now
        if persistCameras(cameras) { enableAutomaticReconnection(for: cameras[index].id) }
        connectingCameraID = nil
    }

    /// Called after initial-handshake BLE disconnection; success and not-found results reconnect immediately.
    /// A not-found result still requires the subsequent Nikon handshake before the connection becomes ready.
    private func showPairingPicker() {
        connectionState = .showingPairingPicker
        isPairingPickerPresented = true
        let present = presentPicker
        pickerTask = Task { @MainActor [weak self] in
            let outcome = await present()
            guard let self else { return }
            self.isPairingPickerPresented = false
            self.pickerTask = nil
            guard self.connectionState == .showingPairingPicker else { return }
            self.firstPairingRequested = false
            switch outcome {
            case .completed, .alreadyConnected, .notFound:
                self.finishPairingAndReconnect()
            case .cancelled:
                self.pairingTarget = nil
                self.connectionState = .disconnected
            case .failed(let detail):
                self.fail(CameraFailure(detail, recovery: .userAction))
            case .simulatorUnavailable:
                self.fail(CameraFailure("Use a physical iPhone for system pairing.", recovery: .userAction))
            }
        }
    }

    /// Processes transport events and advances the connection flow; session-tagged events must match the
    /// current session.
    private func handle(_ event: CameraTransportEvent) {
        switch event {
        case .stateChanged(let state):
            bluetoothState = state
            if state == .poweredOn {
                resumeAutomaticReconnection()
                resumeVisibleDiscovery()
                return
            }
            cancelRetry()
            isScanning = false
            devices.removeAll()
            if reconnectionTarget != nil, state == .unknown || state == .resetting { return }
            let hadFlow = activeDevice != nil || isConnectionOperationInProgress
            stopScanning()
            cancelOperation()
            handshake.reset()
            locationSync.connectionEnded()
            sessionID = nil
            activeDevice = nil
            capabilities = nil
            currentIdentity = nil
            connectingCameraID = nil
            pairingTarget = nil
            firstPairingRequested = false
            if hadFlow {
                let failure = CameraFailure("Bluetooth is unavailable.")
                lastFailure = failure
                connectionState = .failed(failure.message)
            }
        case .scanningChanged(let isScanning):
            self.isScanning = isBluetoothAllowed() && (isNearbyScanningEnabled || reconnectionTarget != nil) && isScanning
        case .discovered(let device, let manufacturer):
            guard isBluetoothAllowed(), isScanning, bluetoothState == .poweredOn else { return }
            if isNearbyScanningEnabled, !devices.contains(where: { $0.id == device.id }) { devices.append(device) }
            if let target = reconnectionTarget,
               NikonCameraMatcher.matches(target, identifier: device.id, manufacturerData: manufacturer,
                                          knownCameras: knownCameras) {
                beginConnection(device, camera: target, firstPairing: false)
            }
        case .discovering(let token):
            guard token == sessionID, connectionState == .connecting else { return }
            connectionState = .discovering
            armTimeout("Discovering services and characteristics")
        case .connected(let token, let capabilities):
            guard token == sessionID, connectionState == .discovering else { return }
            guard capabilities.supportsHandshake, let identity = currentIdentity else {
                fail(CameraFailure("PAIR, NOT1 or ID is missing or incompatible.", recovery: .userAction))
                return
            }
            self.capabilities = capabilities
            connectionState = .handshaking
            perform(handshake.start(stage1: makeStage1(identity)))
        case .subscriptionChanged(let token, let characteristic, let enabled, let error):
            guard token == sessionID, connectionState == .handshaking else { return }
            if let error { fail(error) }
            else if !enabled { fail(CameraFailure("Handshake subscription was disabled.")) }
            else { perform(handshake.subscribed(characteristic)) }
        case .valueReceived(let token, let characteristic, let data):
            guard token == sessionID, connectionState == .handshaking else { return }
            do { perform(try handshake.receive(data, from: characteristic)) }
            catch { fail(CameraFailure(error: error, recovery: .userAction)) }
        case .writeCompleted(let token, let characteristic, let error):
            guard token == sessionID else { return }
            if characteristic == .location, connectionState == .ready {
                locationSync.acknowledge(error: error)
            } else if connectionState == .handshaking {
                if let error { fail(error) }
                else { perform(handshake.acknowledged(characteristic)) }
            }
        case .failed(let token, let error):
            guard token == sessionID, connectionState != .disconnecting else { return }
            fail(error)
        case .disconnected(let token, let error):
            guard token == sessionID else { return }
            defer { resumeVisibleDiscovery() }
            let state = connectionState
            cancelOperation()
            handshake.reset()
            locationSync.connectionEnded()
            sessionID = nil
            activeDevice = nil
            capabilities = nil
            currentIdentity = nil
            connectingCameraID = nil
            if state == .disconnectingForPairing {
                showPairingPicker()
            } else {
                firstPairingRequested = false
                if state == .disconnecting {
                    connectionState = .disconnected
                } else {
                    if case .failed = state {
                        // Keep the original operation failure, including ATT domain and code.
                    } else {
                        lastFailure = error ?? CameraFailure("Camera disconnected.")
                        connectionState = .failed(lastFailure?.message ?? "Camera disconnected.")
                    }
                    scheduleAutomaticReconnection()
                }
            }
        }
    }
}
