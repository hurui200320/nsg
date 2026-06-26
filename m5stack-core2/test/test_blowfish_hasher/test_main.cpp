#include <unity.h>

#include "BlowfishHasher.h"

void testCapturedCameraHashMatchesFurble() {
    static const uint32_t blocks[] = {
        0xcd32687f, 0xa9e28a30,
        0x29fa2680, 0x5e3d94b9,
        0xdbe113ec, 0x44a17d67
    };

    BlowfishHasher hasher;
    BlowfishHasher::HashResult result = hasher.hash(blocks, 6);

    TEST_ASSERT_EQUAL_UINT32(0xe4f2b3a8, result.left);
    TEST_ASSERT_EQUAL_UINT32(0x136ad516, result.right);
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(testCapturedCameraHashMatchesFurble);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(testCapturedCameraHashMatchesFurble);
    UNITY_END();

    return 0;
}

#endif
