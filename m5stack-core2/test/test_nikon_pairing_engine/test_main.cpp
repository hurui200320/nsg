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
static Esp32RandomGenerator random_generator;
#else
static NativeRandomGenerator random_generator;
#endif

static BlowfishHasher hasher;
static NikonPairingEngine engine(random_generator, hasher);

void test_stage1_device_has_required_lsb() {
    const PairingMessage stage1 = engine.create_stage1(nullptr, nullptr);

    TEST_ASSERT_EQUAL_UINT8(0x01, stage1.stage);
    TEST_ASSERT_EQUAL_UINT8(0x01, static_cast<uint8_t>(stage1.device & 0xFFU));
}

void test_stage1_device_is_stable_when_reusing_saved_camera() {
    const uint32_t saved_device = 0xAABBCCDDU;
    const uint32_t saved_nonce = 0x11223344U;
    // note: with invalid input, we don't check
    // we always assume caller pass in valid device value
    const PairingMessage stage1 = engine.create_stage1(&saved_device, &saved_nonce);

    TEST_ASSERT_EQUAL_UINT32(saved_device, stage1.device);
    TEST_ASSERT_EQUAL_UINT32(saved_nonce, stage1.nonce);
}

void test_captured_stage2_finds_salt_six_and_builds_expected_stage3() {
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

    const PairingMessage stage3 = engine.verify_stage2_and_build_stage3(stage1, stage2);

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

void test_stage3_fails_with_zero_stage2() {
    const PairingMessage stage1 = engine.create_stage1(nullptr, nullptr);
    const PairingMessage stage2(0x02, 0ULL, 0U, 0U);

    const PairingMessage stage3 = engine.verify_stage2_and_build_stage3(stage1, stage2);

    // With zero stage2, salt verification should fail and return a zeroed message.
    // Since we return value, not pointer, this is the best we can do.
    TEST_ASSERT_EQUAL_UINT8(0x00, stage3.stage);
    TEST_ASSERT_EQUAL_UINT64(0ULL, stage3.timestamp);
    TEST_ASSERT_EQUAL_UINT32(0U, stage3.device);
    TEST_ASSERT_EQUAL_UINT32(0U, stage3.nonce);
}

void test_extract_serial_reads_stage4_bytes() {
    // Stage 4 payload where bytes 9..16 spell "Z50_2000".
    const PairingMessage stage4(
        0x04,
        0x0123456789ABCDEFULL,
        0x5F30355AU,
        0x30303032U
    );

    char serial[9];
    engine.extract_serial(stage4, serial);

    TEST_ASSERT_EQUAL_STRING("Z50_2000", serial);
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(test_stage1_device_has_required_lsb);
    RUN_TEST(test_stage1_device_is_stable_when_reusing_saved_camera);
    RUN_TEST(test_captured_stage2_finds_salt_six_and_builds_expected_stage3);
    RUN_TEST(test_stage3_fails_with_zero_stage2);
    RUN_TEST(test_extract_serial_reads_stage4_bytes);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_stage1_device_has_required_lsb);
    RUN_TEST(test_stage1_device_is_stable_when_reusing_saved_camera);
    RUN_TEST(test_captured_stage2_finds_salt_six_and_builds_expected_stage3);
    RUN_TEST(test_stage3_fails_with_zero_stage2);
    RUN_TEST(test_extract_serial_reads_stage4_bytes);
    UNITY_END();

    return 0;
}

#endif
