import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonHandshakeTests {
    @Test("Early indications and success do not wait for Stage 1 acknowledgement")
    func earlyIndicationsAdvanceBeforeStage1Acknowledgement() throws {
        var handshake = makeStartedHandshake()
        let stage3Effects = try handshake.receive(CameraTestContext.stage2.data, from: .pairing)
        #expect(handshake.phase == .waitingStage4)
        #expect(
            stage3Effects.contains {
                if case .write(.pairing, _) = $0 {
                    return true
                }
                return false
            }
        )
        _ = try handshake.receive(Data([1, 0]), from: .success)
        let stage4 = NikonPairingMessage(stage: 4, timestamp: 0, device: 0, nonce: 0)
        let effects = try handshake.receive(stage4.data, from: .pairing)
        #expect(effects.contains(.write(.controllerName, NikonHandshake.controllerNameData)))
        #expect(handshake.phase == .writingName)
        _ = handshake.acknowledged(.pairing)
        #expect(handshake.acknowledged(.controllerName) == [.completed])
    }

    @Test("Missing NOT1 falls back to exactly one padded controller name write")
    func missingSuccessNotificationWritesPaddedNameOnce() throws {
        var handshake = makeStartedHandshake()
        _ = try handshake.receive(CameraTestContext.stage2.data, from: .pairing)
        let stage4 = NikonPairingMessage(stage: 4, timestamp: 0, device: 0, nonce: 0)
        #expect(try handshake.receive(stage4.data, from: .pairing).contains(.deferNameWrite))
        #expect(handshake.writeName().contains(.write(.controllerName, NikonHandshake.controllerNameData)))
        #expect(handshake.writeName().isEmpty)
        var expectedName = Data("NSG-iOS".utf8)
        expectedName.append(Data(repeating: 0, count: 25))
        #expect(NikonHandshake.controllerNameData == expectedName)
    }

    @Test("Stage 2 timeout permits one read only after the initial write acknowledgement")
    func stage2TimeoutReadsOnceAfterStage1Acknowledgement() {
        var handshake = makeStartedHandshake()
        #expect(handshake.recoverStage2Timeout(canReadPair: true) == nil)
        _ = handshake.acknowledged(.pairing)
        #expect(handshake.recoverStage2Timeout(canReadPair: true)?.contains(.readPair) == true)
        #expect(handshake.recoverStage2Timeout(canReadPair: true) == nil)
    }

    @Test("Stage 1 is written only after PAIR and NOT1 subscriptions complete")
    func subscriptionsPrecedeStage1Write() {
        var handshake = NikonHandshake()
        let startEffects = handshake.start(stage1: CameraTestContext.stage1)
        #expect(handshake.phase == .subscribingPair)
        #expect(startEffects.contains(.subscribe(.pairing)))
        #expect(!startEffects.contains(.write(.pairing, CameraTestContext.stage1.data)))

        let pairEffects = handshake.subscribed(.pairing)
        #expect(handshake.phase == .subscribingSuccess)
        #expect(pairEffects.contains(.subscribe(.success)))
        #expect(!pairEffects.contains(.write(.pairing, CameraTestContext.stage1.data)))

        let successEffects = handshake.subscribed(.success)
        #expect(handshake.phase == .waitingStage2)
        #expect(successEffects.contains(.write(.pairing, CameraTestContext.stage1.data)))
    }

    @Test("Stage 2 timeout cannot read a non-readable PAIR characteristic")
    func stage2RecoveryRequiresReadCapability() {
        var handshake = makeStartedHandshake()
        _ = handshake.acknowledged(.pairing)

        #expect(handshake.recoverStage2Timeout(canReadPair: false) == nil)
    }

    private func makeStartedHandshake() -> NikonHandshake {
        var handshake = NikonHandshake()
        _ = handshake.start(stage1: CameraTestContext.stage1)
        _ = handshake.subscribed(.pairing)
        _ = handshake.subscribed(.success)
        return handshake
    }
}
