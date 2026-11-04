import Foundation
import CoreLocation
import Observation

/// GEO write lifecycle; sent means the camera acknowledged the write, not that a photo contains GPS data.
enum LocationTransferState: Equatable {
    case idle
    case sending
    case sent
    case failed(String)
}

/// Sends acquired fixes with throttling and GEO acknowledgements. AppServiceController owns acquisition;
/// camera session changes only reset transfer state.
@MainActor
@Observable
final class LocationSyncCoordinator {
    let source: any LocationProviding
    private(set) var transferState: LocationTransferState = .idle
    private(set) var lastSentLocation: CLLocation?
    /// Time of the last successful write acknowledgement, used for throttling; reset when sharing is enabled
    /// again.
    private(set) var lastSentAt: Date?

    /// Application policy installed by AppServiceController; also gates direct and manual submissions.
    @ObservationIgnored var isLocationAllowed: () -> Bool = { true }
    /// Camera availability bound during service initialization; consulted before submitting a fix.
    @ObservationIgnored var isAvailable: () -> Bool = { false }
    /// Submission callback bound during service initialization; each submitted payload requires a result
    /// through acknowledge.
    @ObservationIgnored var submit: (Data) -> Void = { _ in }
    /// Bound during service initialization; requests connection recovery after GEO acknowledgement timeout or
    /// ATT 0x80 rejection.
    @ObservationIgnored var onConnectionFailure: (CameraFailure) -> Void = { _ in }
    @ObservationIgnored private let scheduler: any CameraScheduling
    @ObservationIgnored private var pendingLocation: CLLocation?
    @ObservationIgnored private var writeTimer: CameraTimer?
    @ObservationIgnored private var writeID: UUID?
    @ObservationIgnored private var isTransferPaused = false

    var sendInterval: TimeInterval = 10
    static let acknowledgementTimeout: TimeInterval = 15

    init(source: any LocationProviding, scheduler: any CameraScheduling) {
        self.source = source
        self.scheduler = scheduler
    }

    /// Called when app location use resumes; retains any in-flight write until its acknowledgement.
    func resumeSending() {
        isTransferPaused = false
        if pendingLocation == nil { transferState = .idle }
        lastSentAt = nil
    }

    /// Called after handshake completion; sends an available precise fix without restarting acquisition.
    func connectionReady() {
        guard source.hasFullAccuracy, let location = source.latestLocation else { return }
        send(location, bypassInterval: false)
    }

    /// Called for manual sending; bypasses only the interval, never quality checks or an in-flight write.
    func sendCurrentLocation() {
        guard isLocationAllowed(), source.isRunning, isAvailable() else { return }
        guard source.hasFullAccuracy, let location = source.latestLocation else {
            if pendingLocation == nil { transferState = .failed("Precise location is not available yet.") }
            return
        }
        send(location)
    }

    /// Validates and submits automatic or manual fixes; true means submitted, with success determined by
    /// acknowledgement.
    /// bypassInterval skips only throttling; after acknowledgement timeout, close the connection before
    /// submitting another write.
    @discardableResult
    func send(_ location: CLLocation, bypassInterval: Bool = true) -> Bool {
        guard isLocationAllowed(), source.isRunning, isAvailable(),
              !isTransferPaused, pendingLocation == nil else { return false }
        if !bypassInterval, let lastSentAt,
           scheduler.now.timeIntervalSince(lastSentAt) < sendInterval { return false }
        if let rejection = LocationQuality.rejection(
            for: location, now: scheduler.now, maximumHorizontalAccuracy: source.maximumHorizontalAccuracy
        ) {
            transferState = .failed(rejection.message)
            return false
        }
        do {
            let data = try NikonGeoPayload.make(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                altitude: Int(location.altitude.rounded(.towardZero)), date: location.timestamp
            )
            let token = UUID()
            writeID = token
            pendingLocation = location
            transferState = .sending
            writeTimer = scheduler.schedule(after: Self.acknowledgementTimeout) { [weak self] in
                guard let self, self.writeID == token else { return }
                self.finishPendingWrite()
                self.isTransferPaused = true
                self.transferState = .failed("GPS write acknowledgement timed out.")
                self.onConnectionFailure(CameraFailure("GPS write acknowledgement timed out. Reconnecting."))
            }
            submit(data)
            return true
        } catch {
            isTransferPaused = true
            transferState = .failed(error.localizedDescription)
            return false
        }
    }

    /// Records a GEO acknowledgement; failures pause sending and may request recovery without stopping acquisition.
    func acknowledge(error: CameraFailure?) {
        guard let location = pendingLocation else { return }
        finishPendingWrite()
        if let error {
            isTransferPaused = true
            transferState = .failed(error.diagnosticDescription)
            if error.requiresGeoReconnection { onConnectionFailure(error) }
            return
        }
        lastSentLocation = location
        lastSentAt = scheduler.now
        transferState = .sent
    }

    /// Clears pending writes on connection termination while preserving failure details and app acquisition.
    func connectionEnded() {
        finishPendingWrite()
        if case .failed = transferState { return }
        transferState = .idle
    }

    /// Called before a new BLE session; clears transfer state and history without changing app acquisition.
    func resetForConnection() {
        connectionEnded()
        isTransferPaused = false
        transferState = .idle
        lastSentLocation = nil
        lastSentAt = nil
    }

    private func finishPendingWrite() {
        writeTimer?.cancel()
        writeTimer = nil
        writeID = nil
        pendingLocation = nil
    }
}
