import Foundation
import CoreBluetooth
import CoreLocation

extension BluetoothService {
    enum LocationTransferState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    var canSendLocation: Bool {
        connectionState == .ready &&
        activePeripheral?.state == .connected &&
        characteristics[geoUUID]?.properties.contains(.write) == true
    }

    /// Send the first valid location immediately, then at least 10 seconds apart. Manual sends can bypass the interval.
    func startLocationSync() {
        guard canSendLocation, !locationService.isRunning else { return }
        locationTransferState = .idle
        locationService.start { [weak self] location in
            guard let self else { return }
            guard self.canSendLocation else {
                self.stopLocationSync()
                return
            }
            if let lastSent = self.lastLocationSentAt,
               Date().timeIntervalSince(lastSent) < 10 {
                return
            }
            self.sendLocation(location)
        }
    }

    func stopLocationSync() {
        locationService.stop()
        // Submitted ATT writes must wait for acknowledgement or timeout; never apply a late acknowledgement to the next write.
    }

    func sendCurrentLocation() {
        guard locationService.hasFullAccuracy,
              let location = locationService.latestLocation else {
            locationTransferState = .failed("Precise location is not available yet")
            return
        }
        sendLocation(location)
    }

    @discardableResult
    func sendLocation(_ location: CLLocation, now: Date = Date()) -> Bool {
        guard canSendLocation, let peripheral = activePeripheral,
              let characteristic = characteristics[geoUUID] else { return false }
        guard pendingWrite == nil, writeQueue.isEmpty else { return false }
        guard LocationQuality.isUsable(location, now: now) else {
            locationTransferState = .failed("Location not sent: stale fix, insufficient accuracy, or invalid altitude")
            return false
        }
        do {
            // Use the location sample's timestamp and altitude; do not disguise stale fixes with the current time or send test coordinates.
            let data = try NikonGeoPayload.make(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: Int(location.altitude.rounded(.towardZero)),
                date: location.timestamp
            )
            guard data.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
                stopLocationSync()
                locationTransferState = .failed("GEO data exceeds the camera's maximum write length")
                return false
            }
            let token = UUID()
            geoWriteID = token
            pendingWrite = .geo
            pendingGeoLocation = location
            locationTransferState = .sending
            geoWriteTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                guard let self, self.geoWriteID == token else { return }
                // Close the connection after a timeout to avoid confusing old GEO acknowledgements with subsequent writes.
                self.fail("GPS write acknowledgement timed out. Reconnect the camera.")
                self.locationTransferState = .failed("GPS write acknowledgement timed out")
            }
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            return true
        } catch {
            stopLocationSync()
            locationTransferState = .failed(describe(error))
            return false
        }
    }

    func handleGeoWriteResponse(_ peripheral: CBPeripheral, error: Error?) {
        guard peripheral === activePeripheral, connectionState == .ready,
              pendingWrite == .geo else { return }
        geoWriteTask?.cancel()
        geoWriteTask = nil
        geoWriteID = nil
        let sentLocation = pendingGeoLocation
        pendingGeoLocation = nil
        pendingWrite = nil
        if let error {
            stopLocationSync()
            locationTransferState = .failed(describe(error))
            return
        }
        lastSentLocation = sentLocation
        lastLocationSentAt = Date()
        locationTransferState = .sent
    }

    func resetLocationTransfer() {
        stopLocationSync()
        geoWriteTask?.cancel()
        geoWriteTask = nil
        geoWriteID = nil
        pendingGeoLocation = nil
        locationTransferState = .idle
        lastSentLocation = nil
        lastLocationSentAt = nil
    }
}
