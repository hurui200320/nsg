import Foundation
import Testing

@testable import NSG

@MainActor
struct NikonPairingProtocolTests {
    @Test("Handshake messages use the protocol's little-endian byte order")
    func pairingMessageUsesLittleEndianFields() throws {
        let bytes = Data([
            2,
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0x44, 0x33, 0x22, 0x11,
            0x88, 0x77, 0x66, 0x55,
        ])
        let message = try NikonPairingMessage(data: bytes)
        #expect(message.stage == 2)
        #expect(message.timestamp == 0x0102_0304_0506_0708)
        #expect(message.device == 0x1122_3344)
        #expect(message.nonce == 0x5566_7788)
        #expect(message.data == bytes)
    }

    @Test("Reject truncated and oversized handshake messages", arguments: [0, 16, 18])
    func pairingMessageRejectsInvalidLength(count: Int) {
        #expect(throws: NikonPairingError.self) {
            _ = try NikonPairingMessage(data: Data(repeating: 0, count: count))
        }
    }

    @Test("Captured Stage 2 produces the exact Stage 3 wire bytes")
    func capturedChallengeProducesReferenceResponse() throws {
        // Captured Z50 II vector shared with Android's NikonPairingEngineTest.
        let stage1 = CameraTestContext.stage1
        let stage2 = CameraTestContext.stage2
        let response = try NikonPairingProtocol.response(to: stage2, stage1: stage1)
        #expect(
            response.data
                == Data([
                    3, 0xDB, 0xE1, 0x13, 0xEC, 0x44, 0xA1, 0x7D, 0x67,
                    0x53, 0xAD, 0xF1, 0x79, 0x35, 0x8A, 0x83, 0x23,
                ])
        )
    }

    @Test("Invalid camera challenges are rejected")
    func responseRejectsUnvalidatedChallenge() {
        #expect(throws: NikonPairingError.self) {
            _ = try NikonPairingProtocol.response(
                to: NikonPairingMessage(stage: 2, timestamp: 0, device: 0, nonce: 0),
                stage1: NikonPairingMessage(stage: 1, timestamp: 1, device: 1, nonce: 42)
            )
        }
    }

    @Test("Stage 1 retains the supplied controller identity")
    func stage1RetainsControllerDeviceAndNonce() {
        let message = NikonPairingProtocol.makeStage1(device: 0x1122_3301, nonce: 42)

        #expect(message.stage == 1)
        #expect(message.device == 0x1122_3301)
        #expect(message.nonce == 42)
    }
}
