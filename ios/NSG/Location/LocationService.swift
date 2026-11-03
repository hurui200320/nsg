import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService {
    private(set) var isRunning = false
    private(set) var latestLocation: CLLocation?
    private(set) var hasFullAccuracy = false
    private(set) var status = "Location sharing is off."

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var runID: UUID?

    /// Started by an explicit user action in the foreground; the system requests When In Use location access and temporary full accuracy.
    func start(onLocation: @escaping @MainActor (CLLocation) -> Void) {
        guard !isRunning else { return }
        let token = UUID()
        runID = token
        isRunning = true
        hasFullAccuracy = false
        latestLocation = nil
        status = "Waiting for precise location…"
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
                        self.status = "Enable Location Services in Settings."
                    } else if update.authorizationDenied || update.authorizationRestricted {
                        self.status = "Allow location access in Settings."
                    } else if update.authorizationRequestInProgress {
                        self.status = "Allow location access to send GPS to your camera."
                    } else if update.accuracyLimited {
                        self.status = "Enable Precise Location in Settings."
                    } else if let location = update.location {
                        self.hasFullAccuracy = true
                        self.latestLocation = location
                        if LocationQuality.isUsable(location) {
                            self.status = "Precise location available."
                            onLocation(location)
                        } else {
                            self.status = "Waiting for a fresh fix with accuracy within 20 m and valid altitude…"
                        }
                    } else {
                        self.status = "Waiting for a GPS fix. Try moving outdoors."
                    }
                }
            } catch {
                guard !Task.isCancelled, self?.runID == token else { return }
                self?.status = "Location failed: \(error.localizedDescription)"
            }
        }
    }

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
        status = "Location sharing is off."
    }
}
