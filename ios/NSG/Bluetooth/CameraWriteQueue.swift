import Foundation

/// Serializes writes because ATT acknowledgements identify characteristics, not requests; allows one in flight
/// and clears on disconnect.
struct CameraWriteQueue {
    struct Request: Equatable {
        let characteristic: NikonCharacteristic
        let data: Data
    }

    private var queued: [Request] = []
    private var pending: Request?

    mutating func enqueue(_ data: Data, to characteristic: NikonCharacteristic) {
        queued.append(Request(characteristic: characteristic, data: data))
    }

    /// Claims the next request before sending; returns nil while another is pending. A claimed request must be
    /// sent or the connection terminated.
    mutating func next() -> Request? {
        guard pending == nil, !queued.isEmpty else { return nil }
        let request = queued.removeFirst()
        pending = request
        return request
    }

    /// Called on a write callback; releases a matching pending request, otherwise returns false without
    /// changing state.
    mutating func acknowledge(_ characteristic: NikonCharacteristic) -> Bool {
        guard pending?.characteristic == characteristic else { return false }
        pending = nil
        return true
    }

    /// Called on connection cancellation or termination; also discards the pending marker, so do not use for
    /// ordinary pauses.
    mutating func removeAll() {
        queued.removeAll()
        pending = nil
    }
}
