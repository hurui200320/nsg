#include <unity.h>

#include "Utils.h"

void testHexString() {
    static const uint8_t blocks[] = {0xcd, 0x32, 0x68, 0x7f, 0xa9};

    auto result = Utils::hexStr(blocks, sizeof(blocks));

    TEST_ASSERT_EQUAL_STRING("cd32687fa9", result.c_str());
}

void testUint32ToLittleEndian() {
    uint32_t value = 0x12345678u;
    uint8_t arr[4];
    Utils::uint32ToLittleEndian(value, arr);

    static const uint8_t expected[4] = {0x78, 0x56, 0x34, 0x12};
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, arr, 4);
}

void testUint32ToLittleEndianHexString() {
    uint32_t value = 0x12345678u;
    auto result = Utils::uint32ToLittleEndianHexString(value);
    TEST_ASSERT_EQUAL_STRING("78563412", result.c_str());
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(testHexString);
    RUN_TEST(testUint32ToLittleEndian);
    RUN_TEST(testUint32ToLittleEndianHexString);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(testHexString);
    RUN_TEST(testUint32ToLittleEndian);
    RUN_TEST(testUint32ToLittleEndianHexString);
    UNITY_END();

    return 0;
}

#endif
