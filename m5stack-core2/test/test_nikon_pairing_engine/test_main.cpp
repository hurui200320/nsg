#include <unity.h>

#include "BlowfishHasher.h"
#include "NikonPairingEngine.h"
#include "PairingMessage.h"

#ifdef ESP32
#include "Esp32RandomGenerator.h"
#else
#include "NativeRandomGenerator.h"
#endif

#ifdef ESP32
static Esp32RandomGenerator randomGenerator;
#else
static NativeRandomGenerator randomGenerator;
#endif

static BlowfishHasher hasher;
static NikonPairingEngine engine(randomGenerator, hasher);

void testStage1DeviceHasRequiredLsb() {
    const PairingMessage stage1 = engine.createStage1(nullptr, nullptr);

    TEST_ASSERT_EQUAL_UINT8(0x01, stage1.stage);
    TEST_ASSERT_EQUAL_UINT8(0x01, static_cast<uint8_t>(stage1.device & 0xFFU));
}

void testStage1DeviceIsStableWhenReusingSavedCamera() {
    const uint32_t savedDevice = 0xAABBCCDDU;
    const uint32_t savedNonce = 0x11223344U;
    // note: with invalid input, we don't check
    // we always assume caller pass in valid device value
    const PairingMessage stage1 = engine.createStage1(&savedDevice, &savedNonce);

    TEST_ASSERT_EQUAL_UINT32(savedDevice, stage1.device);
    TEST_ASSERT_EQUAL_UINT32(savedNonce, stage1.nonce);
}

void testCapturedStage2FindsSaltSixAndBuildsExpectedStage3() {
    // Real values captured from the Z50_2 camera handshake.
    const PairingMessage stage1(
        0x01,
        0x677da144ec13e1dbULL,
        0x3c3ae501U,
        0x3fdaa451U
    );
    const PairingMessage stage2(
        0x02,
        0xb9943d5e8026fa29ULL,
        0xa8b3f2e4U,
        0x16d56a13U
    );

    const PairingMessage stage3 = engine.verifyStage2AndBuildStage3(stage1, stage2);

    TEST_ASSERT_EQUAL_UINT8(0x03, stage3.stage);
    TEST_ASSERT_EQUAL_UINT64(stage1.timestamp, stage3.timestamp);
    TEST_ASSERT_EQUAL_UINT32(0x79f1ad53U, stage3.device);
    TEST_ASSERT_EQUAL_UINT32(0x23838a35U, stage3.nonce);

    uint8_t encoded[PairingMessage::SIZE];
    stage3.encode(encoded);

    static const uint8_t expected[PairingMessage::SIZE] = {
        0x03,
        0xdb, 0xe1, 0x13, 0xec,
        0x44, 0xa1, 0x7d, 0x67,
        0x53, 0xad, 0xf1, 0x79,
        0x35, 0x8a, 0x83, 0x23
    };
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, encoded, PairingMessage::SIZE);
}

void testStage3FailsWithZeroStage2() {
    const PairingMessage stage1 = engine.createStage1(nullptr, nullptr);
    const PairingMessage stage2(0x02, 0ULL, 0U, 0U);

    const PairingMessage stage3 = engine.verifyStage2AndBuildStage3(stage1, stage2);

    // With zero stage2, salt verification should fail and return a zeroed message.
    // Since we return value, not pointer, this is the best we can do.
    TEST_ASSERT_EQUAL_UINT8(0x00, stage3.stage);
    TEST_ASSERT_EQUAL_UINT64(0ULL, stage3.timestamp);
    TEST_ASSERT_EQUAL_UINT32(0U, stage3.device);
    TEST_ASSERT_EQUAL_UINT32(0U, stage3.nonce);
}

void testExtractSerialReadsStage4Bytes() {
    // Stage 4 payload where bytes 9..16 spell "Z50_2000".
    const PairingMessage stage4(
        0x04,
        0x0123456789ABCDEFULL,
        0x5F30355AU,
        0x30303032U
    );

    char serial[9];
    engine.extractSerial(stage4, serial);

    TEST_ASSERT_EQUAL_STRING("Z50_2000", serial);
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(testStage1DeviceHasRequiredLsb);
    RUN_TEST(testStage1DeviceIsStableWhenReusingSavedCamera);
    RUN_TEST(testCapturedStage2FindsSaltSixAndBuildsExpectedStage3);
    RUN_TEST(testStage3FailsWithZeroStage2);
    RUN_TEST(testExtractSerialReadsStage4Bytes);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(testStage1DeviceHasRequiredLsb);
    RUN_TEST(testStage1DeviceIsStableWhenReusingSavedCamera);
    RUN_TEST(testCapturedStage2FindsSaltSixAndBuildsExpectedStage3);
    RUN_TEST(testStage3FailsWithZeroStage2);
    RUN_TEST(testExtractSerialReadsStage4Bytes);
    UNITY_END();

    return 0;
}

#endif
