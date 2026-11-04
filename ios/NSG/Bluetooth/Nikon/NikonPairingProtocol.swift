import Foundation
import CommonCrypto

// Protocol reference: https://github.com/hurui200320/nsg/blob/master/doc/nikon-z-gps.md
// Timestamp word order follows the working Android NikonPairingEngine implementation.
/// 17-byte PAIR message with little-endian fields; Stage 4 uses the final eight bytes for the camera serial
/// number.
struct NikonPairingMessage: Equatable {
    let stage: UInt8
    let timestamp: UInt64
    let device: UInt32
    let nonce: UInt32

    var data: Data {
        var bytes = [stage]
        bytes += (0..<8).map { UInt8(truncatingIfNeeded: timestamp >> ($0 * 8)) }
        bytes += (0..<4).map { UInt8(truncatingIfNeeded: device >> ($0 * 8)) }
        bytes += (0..<4).map { UInt8(truncatingIfNeeded: nonce >> ($0 * 8)) }
        return Data(bytes)
    }

    init(stage: UInt8, timestamp: UInt64, device: UInt32, nonce: UInt32) {
        self.stage = stage
        self.timestamp = timestamp
        self.device = device
        self.nonce = nonce
    }

    init(data: Data) throws {
        guard data.count == 17 else { throw NikonPairingError.invalidMessage }
        let bytes = Array(data)
        stage = bytes[0]
        timestamp = (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[$1 + 1]) << ($1 * 8) }
        device = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[$1 + 9]) << ($1 * 8) }
        nonce = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[$1 + 13]) << ($1 * 8) }
    }
}

enum NikonPairingError: LocalizedError {
    case invalidMessage
    case unexpectedStage
    case challengeRejected
    case encryptionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidMessage: return "Handshake messages must be 17 bytes long"
        case .unexpectedStage: return "Unexpected handshake stage"
        case .challengeRejected: return "No salt validated the camera challenge; handshake stopped"
        case .encryptionFailed(let status): return "Blowfish computation failed: \(status)"
        }
    }
}

enum NikonPairingProtocol {
    private static let key: [UInt8] = [0xFF, 0xFF, 0xAA, 0x55, 0x11, 0x22, 0x33, 0x00]
    private static let salts: [(UInt32, UInt32)] = [
        (0x704066E4, 0x0433D552), (0xED4B8FAC, 0x15F7E47B),
        (0x24471F11, 0x8B5EA1FC), (0x05960C31, 0x2B8C7F41),
        (0xFDA588C1, 0xEBA8B1F3), (0x99166056, 0x1BD3D550),
        (0xCD32687F, 0xA9E28A30), (0x2A8FE834, 0xDEC7EBF4)
    ]

    /// Starts each handshake with saved device/nonce values and a fresh random timestamp, which is not
    /// wall-clock time.
    static func makeStage1(device: UInt32, nonce: UInt32) -> NikonPairingMessage {
        NikonPairingMessage(stage: 1, timestamp: UInt64.random(in: .min ... .max),
                            device: device, nonce: nonce)
    }

    /// Validates Stage 2 and builds Stage 3 using the Stage 1 actually sent in this attempt; throws if
    /// validation fails.
    static func response(to challenge: NikonPairingMessage,
                         stage1: NikonPairingMessage) throws -> NikonPairingMessage {
        guard stage1.stage == 1, challenge.stage == 2 else {
            throw NikonPairingError.unexpectedStage
        }
        let camera = timestampWords(challenge.timestamp)
        let controller = timestampWords(stage1.timestamp)
        for salt in salts {
            let expected = try hash([salt.0, salt.1] + camera + controller)
            guard expected.0 == challenge.device.byteSwapped,
                  expected.1 == challenge.nonce.byteSwapped else { continue }
            let result = try hash([salt.0, salt.1] + controller + camera)
            return NikonPairingMessage(stage: 3, timestamp: stage1.timestamp,
                                       device: result.0.byteSwapped, nonce: result.1.byteSwapped)
        }
        throw NikonPairingError.challengeRejected
    }

    private static func timestampWords(_ value: UInt64) -> [UInt32] {
        // Android hashes byte-swapped low then high halves, unlike the prose reference.
        [UInt32(truncatingIfNeeded: value).byteSwapped,
         UInt32(truncatingIfNeeded: value >> 32).byteSwapped]
    }

    private static func hash(_ words: [UInt32]) throws -> (UInt32, UInt32) {
        var left: UInt32 = 0x01020304
        var right: UInt32 = 0x05060708
        for offset in stride(from: 0, to: words.count, by: 2) {
            let input = bigEndianBytes(words[offset] ^ left) + bigEndianBytes(words[offset + 1] ^ right)
            var output = [UInt8](repeating: 0, count: 8)
            var count = 0
            let status = key.withUnsafeBytes { keyBytes in
                input.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmBlowfish),
                                CCOptions(kCCOptionECBMode), keyBytes.baseAddress, key.count,
                                nil, inputBytes.baseAddress, input.count,
                                outputBytes.baseAddress, 8, &count)
                    }
                }
            }
            guard status == kCCSuccess, count == 8 else {
                throw NikonPairingError.encryptionFailed(status)
            }
            left = output[0..<4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            right = output[4..<8].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        return (left, right)
    }

    private static func bigEndianBytes(_ word: UInt32) -> [UInt8] {
        stride(from: 24, through: 0, by: -8).map { UInt8(truncatingIfNeeded: word >> $0) }
    }
}
