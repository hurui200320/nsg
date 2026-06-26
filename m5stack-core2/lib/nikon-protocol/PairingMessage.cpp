#include "PairingMessage.h"

#include <tuple>

PairingMessage::PairingMessage(
    uint8_t stage, uint64_t timestamp, uint32_t device, uint32_t nonce
) : stage(stage), timestamp(timestamp), device(device), nonce(nonce) {
}

void PairingMessage::encode(uint8_t *buffer) const {
    buffer[0] = stage;

    buffer[1] = static_cast<uint8_t>(timestamp & 0xFF);
    buffer[2] = static_cast<uint8_t>((timestamp >> 8) & 0xFF);
    buffer[3] = static_cast<uint8_t>((timestamp >> 16) & 0xFF);
    buffer[4] = static_cast<uint8_t>((timestamp >> 24) & 0xFF);
    buffer[5] = static_cast<uint8_t>((timestamp >> 32) & 0xFF);
    buffer[6] = static_cast<uint8_t>((timestamp >> 40) & 0xFF);
    buffer[7] = static_cast<uint8_t>((timestamp >> 48) & 0xFF);
    buffer[8] = static_cast<uint8_t>((timestamp >> 56) & 0xFF);

    buffer[9] = static_cast<uint8_t>(device & 0xFF);
    buffer[10] = static_cast<uint8_t>((device >> 8) & 0xFF);
    buffer[11] = static_cast<uint8_t>((device >> 16) & 0xFF);
    buffer[12] = static_cast<uint8_t>((device >> 24) & 0xFF);

    buffer[13] = static_cast<uint8_t>(nonce & 0xFF);
    buffer[14] = static_cast<uint8_t>((nonce >> 8) & 0xFF);
    buffer[15] = static_cast<uint8_t>((nonce >> 16) & 0xFF);
    buffer[16] = static_cast<uint8_t>((nonce >> 24) & 0xFF);
}

PairingMessage PairingMessage::decode(const uint8_t *data) {
    uint8_t stage = data[0];

    uint64_t timestamp =
            (static_cast<uint64_t>(data[1])) |
            (static_cast<uint64_t>(data[2]) << 8) |
            (static_cast<uint64_t>(data[3]) << 16) |
            (static_cast<uint64_t>(data[4]) << 24) |
            (static_cast<uint64_t>(data[5]) << 32) |
            (static_cast<uint64_t>(data[6]) << 40) |
            (static_cast<uint64_t>(data[7]) << 48) |
            (static_cast<uint64_t>(data[8]) << 56);

    uint32_t device =
            (static_cast<uint32_t>(data[9])) |
            (static_cast<uint32_t>(data[10]) << 8) |
            (static_cast<uint32_t>(data[11]) << 16) |
            (static_cast<uint32_t>(data[12]) << 24);

    uint32_t nonce =
            (static_cast<uint32_t>(data[13])) |
            (static_cast<uint32_t>(data[14]) << 8) |
            (static_cast<uint32_t>(data[15]) << 16) |
            (static_cast<uint32_t>(data[16]) << 24);

    return PairingMessage(stage, timestamp, device, nonce);
}

bool PairingMessage::operator==(const PairingMessage &other) const {
    return std::tie(stage, timestamp, device, nonce) ==
           std::tie(other.stage, other.timestamp, other.device, other.nonce);
}
