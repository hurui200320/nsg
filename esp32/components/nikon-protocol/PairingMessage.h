/**
 * C++ port of PairingMessage from kotlin-poc.
 *
 * A 17-byte pairing message used in the Nikon smart-device handshake.
 *
 * Layout (little-endian on the wire):
 *   byte 0       stage
 *   bytes 1-8    timestamp (uint64)
 *   bytes 9-12   device (uint32)
 *   bytes 13-16  nonce (uint32)
 */

#ifndef PAIRING_MESSAGE_H
#define PAIRING_MESSAGE_H

#include <cstddef>
#include <cstdint>
#include <string>

class PairingMessage {
public:
    static constexpr size_t SIZE = 17;

    uint8_t stage;
    uint64_t timestamp;
    uint32_t device;
    uint32_t nonce;

    PairingMessage(uint8_t stage, uint64_t timestamp, uint32_t device, uint32_t nonce);

    /**
     * Encodes this message into the supplied 17-byte buffer.
     * The caller must ensure [buffer] has room for at least [SIZE] bytes.
     */
    void encode(uint8_t *buffer) const;

    /**
     * Decodes a PairingMessage from a 17-byte buffer.
     * The caller must ensure [data] has at least [SIZE] bytes.
     */
    static PairingMessage decode(const uint8_t *data);

    bool operator==(const PairingMessage &other) const;

    std::string toString() const;
};

#endif // PAIRING_MESSAGE_H
