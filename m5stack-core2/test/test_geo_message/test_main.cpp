#include <unity.h>

#include "GeoMessage.h"

void testFromDecimalEncodeDecodeRoundTrip() {
    GeoMessage original = GeoMessage::fromDecimal(
        41.289491667, 87.10866, 237, 11,
        2026, 6, 25, 12, 42, 29, 90,
        1
    );

    uint8_t encoded[GeoMessage::SIZE];
    original.encode(encoded, sizeof(encoded));

    TEST_ASSERT_EQUAL_UINT8(41, GeoMessage::SIZE);
    static const uint8_t expected[GeoMessage::SIZE] = {
        // header 0x007F little-endian
        0x7F, 0x00,
        // latitude: N 41d 17.3695m
        'N', 41, 17, 36, 95,
        // longitude: E 87d 6.5196m
        'E', 87, 6, 51, 96,
        // satellites, altitude reference 'P', altitude 237
        11, 'P', 0xED, 0x00,
        // time: 2026-06-25 12:42:29
        0xEA, 0x07, 6, 25, 12, 42, 29,
        // centiseconds, valid
        90, 1,
        // datum "WGS-84"
        'W', 'G', 'S', '-', '8', '4',
        // padding
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    };
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, encoded, GeoMessage::SIZE);

    GeoMessage decoded = GeoMessage::decode(encoded, sizeof(encoded));
    TEST_ASSERT_TRUE(original == decoded);
}

void testNegativeAltitudeAndLongitude() {
    GeoMessage original = GeoMessage::fromDecimal(
        -33.868820, -151.209290, -10, 12,
        2024, 1, 15, 8, 30, 45,
        12, 1
    );

    uint8_t encoded[GeoMessage::SIZE];
    original.encode(encoded, sizeof(encoded));

    TEST_ASSERT_EQUAL_UINT8('S', encoded[2]);
    TEST_ASSERT_EQUAL_UINT8('W', encoded[7]);
    TEST_ASSERT_EQUAL_UINT8('M', encoded[13]);
    TEST_ASSERT_EQUAL_UINT8(10, encoded[14]);
    TEST_ASSERT_EQUAL_UINT8(0, encoded[15]);
    TEST_ASSERT_EQUAL_UINT8(12, encoded[23]);

    GeoMessage decoded = GeoMessage::decode(encoded, sizeof(encoded));
    TEST_ASSERT_TRUE(original == decoded);
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(testFromDecimalEncodeDecodeRoundTrip);
    RUN_TEST(testNegativeAltitudeAndLongitude);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(testFromDecimalEncodeDecodeRoundTrip);
    RUN_TEST(testNegativeAltitudeAndLongitude);
    UNITY_END();

    return 0;
}

#endif
