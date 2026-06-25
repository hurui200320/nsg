#include <unity.h>

#include "TimeMessage.h"

void test_encode_decode_round_trip() {
    // 2026 Jun 25 20:18:38 UTC+8
    TimeMessage original(
        2026, 6, 25,
        12, 18, 38,
        0, 8, 0
    );

    uint8_t encoded[TimeMessage::SIZE];
    original.encode(encoded);

    TEST_ASSERT_EQUAL_UINT8(10, TimeMessage::SIZE);

    static const uint8_t expected[TimeMessage::SIZE] = {
        0xEA, 0x07, 0x06, 0x19,
        0x0C, 0x12, 0x26,
        0x00, 0x08, 0x00
    };
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, encoded, TimeMessage::SIZE);

    TimeMessage decoded = TimeMessage::decode(encoded);
    TEST_ASSERT_EQUAL_UINT16(original.year, decoded.year);
    TEST_ASSERT_EQUAL_UINT8(original.month, decoded.month);
    TEST_ASSERT_EQUAL_UINT8(original.day, decoded.day);
    TEST_ASSERT_EQUAL_UINT8(original.hour, decoded.hour);
    TEST_ASSERT_EQUAL_UINT8(original.minute, decoded.minute);
    TEST_ASSERT_EQUAL_UINT8(original.second, decoded.second);
    TEST_ASSERT_EQUAL_INT8(original.dst_offset, decoded.dst_offset);
    TEST_ASSERT_EQUAL_INT8(original.tz_offset_hours, decoded.tz_offset_hours);
    TEST_ASSERT_EQUAL_INT8(original.tz_offset_minutes, decoded.tz_offset_minutes);
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(test_encode_decode_round_trip);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_encode_decode_round_trip);
    UNITY_END();

    return 0;
}

#endif
