import Foundation

/// Advances the handshake from subscriptions, data, and acknowledgements; returns effects for the service to
/// perform I/O and timing.
struct NikonHandshake {
    enum Phase: Equatable {
        case idle, subscribingPair, subscribingSuccess, waitingStage2
        case waitingStage4, waitingSuccess, writingName, complete
    }

    /// Actions the service executes in order, including Bluetooth commands, deadlines, and handshake
    /// completion.
    enum Effect: Equatable {
        case subscribe(NikonCharacteristic)
        case write(NikonCharacteristic, Data)
        case readPair
        case timeout(String, TimeInterval)
        case deferNameWrite
        case completed
    }

    private(set) var phase: Phase = .idle
    private var stage1: NikonPairingMessage?
    private var successSeen = false
    private var stage1Acknowledged = false
    private var stage2ReadRequested = false

    /// Compatibility payload for the ID characteristic; retains the validated ASCII name padded to 32 bytes.
    static var controllerNameData: Data {
        var data = Data("NSG-iOS-Probe".utf8)
        data.append(Data(repeating: 0, count: 32 - data.count))
        return data
    }

    /// Starts after capability validation; clears old state, retains this attempt's Stage 1, and subscribes to
    /// PAIR first.
    mutating func start(stage1: NikonPairingMessage) -> [Effect] {
        self = NikonHandshake()
        self.stage1 = stage1
        phase = .subscribingPair
        return [.timeout("Subscribing to PAIR", 15), .subscribe(.pairing)]
    }

    /// Called after subscription succeeds; enables PAIR, then NOT1, and writes Stage 1 only when both are
    /// ready.
    mutating func subscribed(_ characteristic: NikonCharacteristic) -> [Effect] {
        if phase == .subscribingPair, characteristic == .pairing {
            phase = .subscribingSuccess
            return [.timeout("Subscribing to NOT1", 15), .subscribe(.success)]
        }
        if phase == .subscribingSuccess, characteristic == .success, let stage1 {
            phase = .waitingStage2
            return [.timeout("Waiting for Stage 2", 15), .write(.pairing, stage1.data)]
        }
        return []
    }

    /// Called for PAIR or NOT1 data; validates the challenge and advances phases while tolerating early success
    /// notifications.
    mutating func receive(_ data: Data, from characteristic: NikonCharacteristic) throws -> [Effect] {
        if characteristic == .success {
            guard data == Data([1, 0]) else { return [] }
            successSeen = true
            return phase == .waitingSuccess ? writeName() : []
        }
        guard characteristic == .pairing, phase == .waitingStage2 || phase == .waitingStage4 else { return [] }
        let message = try NikonPairingMessage(data: data)
        if phase == .waitingStage2, message.stage == 2, let stage1 {
            let response = try NikonPairingProtocol.response(to: message, stage1: stage1)
            phase = .waitingStage4
            return [.timeout("Waiting for Stage 4", 15), .write(.pairing, response.data)]
        }
        if phase == .waitingStage4, message.stage == 4 {
            phase = .waitingSuccess
            if successSeen { return writeName() }
            // Some cameras send NOT1 only after the name write.
            return [.timeout("Completing handshake", 15), .deferNameWrite]
        }
        return []
    }

    /// Called after successful write acknowledgement; name acknowledgement completes the handshake, while
    /// indications may precede earlier write acknowledgements.
    mutating func acknowledged(_ characteristic: NikonCharacteristic) -> [Effect] {
        if characteristic == .pairing { stage1Acknowledged = true }
        if characteristic == .controllerName, phase == .writingName {
            phase = .complete
            return [.completed]
        }
        return []
    }

    /// Called on success notification or the three-second fallback; writes the controller name once, only in
    /// waitingSuccess.
    mutating func writeName() -> [Effect] {
        guard phase == .waitingSuccess else { return [] }
        phase = .writingName
        return [.timeout("Writing controller name", 15), .write(.controllerName, Self.controllerNameData)]
    }

    /// Attempts one Stage 2 timeout read after Stage 1 acknowledgement if readable; nil means the service
    /// should fail the timeout.
    mutating func recoverStage2Timeout(canReadPair: Bool) -> [Effect]? {
        guard phase == .waitingStage2, stage1Acknowledged, !stage2ReadRequested, canReadPair else { return nil }
        stage2ReadRequested = true
        return [.timeout("Reading Stage 2", 5), .readPair]
    }

    mutating func reset() { self = NikonHandshake() }
}
