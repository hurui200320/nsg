import Foundation
import CoreLocation
import Observation

/// Collects fixes and publishes authorization/accuracy diagnostics; forwards only fixes that pass quality
/// checks.
@MainActor
@Observable
final class LocationService: LocationProviding {
    private(set) var isRunning = false
    /// Location carried by the current update; may fail quality checks and must be validated before sending.
    private(set) var latestLocation: CLLocation?
    /// The current update reports no accuracy restriction; this alone does not guarantee adequate fix accuracy
    /// or freshness.
    private(set) var hasFullAccuracy = false
    private(set) var status: LocationStatus = .off
    /// A sending threshold, not a guarantee that Core Location can produce this accuracy.
    var maximumHorizontalAccuracy = LocationQuality.maximumHorizontalAccuracy {
        didSet {
            guard hasFullAccuracy, let latestLocation else { return }
            if let reason = LocationQuality.rejection(for: latestLocation, maximumHorizontalAccuracy: maximumHorizontalAccuracy) {
                status = .rejected(reason)
            } else {
                status = .ready
            }
        }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    /// Identifies each acquisition run so an older task cannot clear state belonging to a newer run.
    @ObservationIgnored private var runID: UUID?

    /// Called when the user enables GPS in the foreground; creates service/background sessions and requests
    /// When In Use and temporary full accuracy.
    func start(onLocation: @escaping @MainActor (CLLocation) -> Void) {
        guard !isRunning else { return }
        let token = UUID()
        runID = token
        isRunning = true
        hasFullAccuracy = false
        latestLocation = nil
        status = .waiting
        let session = CLServiceSession(
            authorization: .whenInUse,
            fullAccuracyPurposeKey: "CameraGeotagging"
        )
        self.session = session
        let backgroundSession = CLBackgroundActivitySession()
        self.backgroundSession = backgroundSession

        updatesTask = Task { @MainActor [weak self] in
            defer {
                session.invalidate()
                backgroundSession.invalidate()
                if self?.runID == token {
                    self?.isRunning = false
                    self?.hasFullAccuracy = false
                    self?.latestLocation = nil
                    self?.runID = nil
                    self?.session = nil
                    self?.backgroundSession = nil
                    self?.updatesTask = nil
                }
            }
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard !Task.isCancelled, let self, self.runID == token else { return }
                    self.hasFullAccuracy = false
                    self.latestLocation = nil
                    if update.authorizationDeniedGlobally {
                        self.status = .servicesDisabled
                    } else if update.authorizationDenied || update.authorizationRestricted {
                        self.status = .authorizationDenied
                    } else if update.authorizationRequestInProgress {
                        self.status = .requestingAuthorization
                    } else if update.accuracyLimited {
                        self.status = .accuracyLimited
                    } else if let location = update.location {
                        self.hasFullAccuracy = true
                        self.latestLocation = location
                        if let reason = LocationQuality.rejection(
                            for: location, maximumHorizontalAccuracy: self.maximumHorizontalAccuracy
                        ) {
                            self.status = .rejected(reason)
                        } else {
                            self.status = .ready
                            onLocation(location)
                        }
                    } else {
                        self.status = .waiting
                    }
                }
            } catch {
                guard !Task.isCancelled, self?.runID == token else { return }
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    /// Called when app location use is disabled; cancels updates, invalidates sessions, and clears the fix.
    /// Camera disconnection does not stop acquisition. Safe to repeat.
    func stop() {
        runID = nil
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        isRunning = false
        hasFullAccuracy = false
        latestLocation = nil
        status = .off
    }
}
