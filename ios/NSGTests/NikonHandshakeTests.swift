import Foundation
import Testing
@testable import NSG

@MainActor
struct NikonHandshakeTests {
    private func started() -> NikonHandshake {
        var handshake = NikonHandshake()
        _ = handshake.start(stage1: CameraTestContext.stage1)
        _ = handshake.subscribed(.pairing)
        _ = handshake.subscribed(.success)
        return handshake
    }

    @Test("Early indications and success do not wait for Stage 1 acknowledgement")
    func earlyNotifications() throws {
        var handshake = started()
        #expect(try handshake.receive(CameraTestContext.stage2.data, from: .pairing).contains {
            if case .write(.pairing, _) = $0 { return true }; return false
        })
        _ = try handshake.receive(Data([1, 0]), from: .success)
        let stage4 = NikonPairingMessage(stage: 4, timestamp: 0, device: 0, nonce: 0)
        let effects = try handshake.receive(stage4.data, from: .pairing)
        #expect(effects.contains(.write(.controllerName, NikonHandshake.controllerNameData)))
        #expect(handshake.phase == .writingName)
        _ = handshake.acknowledged(.pairing)
        #expect(handshake.acknowledged(.controllerName) == [.completed])
    }

    @Test("Missing NOT1 falls back to exactly one padded controller name write")
    func delayedName() throws {
        var handshake = started()
        _ = try handshake.receive(CameraTestContext.stage2.data, from: .pairing)
        let stage4 = NikonPairingMessage(stage: 4, timestamp: 0, device: 0, nonce: 0)
        #expect(try handshake.receive(stage4.data, from: .pairing).contains(.deferNameWrite))
        #expect(handshake.writeName().contains(.write(.controllerName, NikonHandshake.controllerNameData)))
        #expect(handshake.writeName().isEmpty)
        #expect(NikonHandshake.controllerNameData.count == 32)
        #expect(NikonHandshake.controllerNameData.prefix(13) == Data("NSG-iOS-Probe".utf8).prefix(13))
    }

    @Test("Stage 2 timeout permits one read only after the initial write acknowledgement")
    func stage2Recovery() {
        var handshake = started()
        #expect(handshake.recoverStage2Timeout(canReadPair: true) == nil)
        _ = handshake.acknowledged(.pairing)
        #expect(handshake.recoverStage2Timeout(canReadPair: true)?.contains(.readPair) == true)
        #expect(handshake.recoverStage2Timeout(canReadPair: true) == nil)
    }

    @Test("Cancelling the handshake cancels both operation and delayed-name timers")
    func cancellation() throws {
        let context = try CameraTestContext()
        defer { context.cleanup() }
        let session = try context.connect()
        context.transport.emit(.writeCompleted(session, .pairing, nil))
        context.transport.emit(.valueReceived(session, .pairing, CameraTestContext.stage2.data))
        context.transport.emit(.writeCompleted(session, .pairing, nil))
        context.transport.emit(.valueReceived(session, .pairing,
            NikonPairingMessage(stage: 4, timestamp: 0, device: 0, nonce: 0).data))
        context.service.disconnect()
        context.scheduler.advance(by: 60)
        #expect(!context.transport.writes.contains { $0.0 == .controllerName })
        #expect(context.transport.disconnections == [session])
    }

    @Test("Discovery and reconnect use different foreground filters; background scans require the service")
    func scanPolicy() {
        #expect(CameraScanPolicy.services(for: .discovery, isForeground: true) == [NikonCharacteristic.serviceUUID])
        #expect(CameraScanPolicy.services(for: .reconnection, isForeground: true) == nil)
        #expect(CameraScanPolicy.services(for: .reconnection, isForeground: false) == [NikonCharacteristic.serviceUUID])
        #expect(CameraScanPolicy.isNikonAdvertisement(services: [], manufacturerData: Data([0x99, 3, 1, 0, 0, 0, 0])))
        #expect(!CameraScanPolicy.isNikonAdvertisement(services: [], manufacturerData: Data([0x98, 3, 1, 0, 0, 0, 0])))
    }
}
