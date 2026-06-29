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
     * Encodes this message into the supplied buffer.
     * Returns true on success, false if [bufferSize] is too small.
     */
    bool encode(uint8_t *buffer, size_t bufferSize) const;

    /**
     * Decodes a PairingMessage from the supplied buffer.
     * Returns a zeroed stage-0 message if [dataSize] is too small.
     */
    static PairingMessage decode(const uint8_t *data, size_t dataSize);

    bool operator==(const PairingMessage &other) const;

    std::string toString() const;
};

#endif // PAIRING_MESSAGE_H
