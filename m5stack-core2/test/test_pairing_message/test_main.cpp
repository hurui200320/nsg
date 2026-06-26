#include <unity.h>

#include "PairingMessage.h"

void testEncodeDecodeRoundTrip() {
    PairingMessage original(
        0x03,
        0x123456789ABCDEF0ULL,
        0xAABBCCDDU,
        0x11223344U
    );

    uint8_t encoded[PairingMessage::SIZE];
    original.encode(encoded);

    TEST_ASSERT_EQUAL_UINT8(17, PairingMessage::SIZE);

    static const uint8_t expected[PairingMessage::SIZE] = {
        // stage
        0x03,
        // timestamp little-endian
        0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12,
        // device little-endian
        0xDD, 0xCC, 0xBB, 0xAA,
        // nonce little-endian
        0x44, 0x33, 0x22, 0x11
    };
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, encoded, PairingMessage::SIZE);

    PairingMessage decoded = PairingMessage::decode(encoded);
    TEST_ASSERT_EQUAL_UINT8(original.stage, decoded.stage);
    TEST_ASSERT_EQUAL_UINT64(original.timestamp, decoded.timestamp);
    TEST_ASSERT_EQUAL_UINT32(original.device, decoded.device);
    TEST_ASSERT_EQUAL_UINT32(original.nonce, decoded.nonce);
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(testEncodeDecodeRoundTrip);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(testEncodeDecodeRoundTrip);
    UNITY_END();

    return 0;
}

#endif
