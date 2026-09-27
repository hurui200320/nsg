#include <unity.h>

#include "BleRetryPolicy.h"

// --- shouldAttemptReconnect ---

void testReconnectNoFailedAttempt() {
    // 0 = no failed attempt on record, always allowed (also covers the
    // first interval after boot where millis() is still small).
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldAttemptReconnect(0, 0, 10000));
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldAttemptReconnect(5000, 0, 10000));
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldAttemptReconnect(500000, 0, 10000));
}

void testReconnectWithinInterval() {
    TEST_ASSERT_FALSE(BleRetryPolicy::shouldAttemptReconnect(5000, 1000, 10000));
    TEST_ASSERT_FALSE(BleRetryPolicy::shouldAttemptReconnect(10000, 1000, 10000));
    TEST_ASSERT_FALSE(BleRetryPolicy::shouldAttemptReconnect(10999, 1000, 10000));
}

void testReconnectIntervalElapsed() {
    // exact boundary counts as elapsed
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldAttemptReconnect(11000, 1000, 10000));
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldAttemptReconnect(999999, 1000, 10000));
}

void testReconnectAcrossWraparound() {
    // millis() wraps at 2^32 ms (~49.7 days); unsigned subtraction must
    // measure the true elapsed time across the wrap.
    const uint32_t lastAttempt = 0xFFFFFFFFu - 3000u + 1u;  // 3s before the wrap
    // 2s after the wrap -> 5s elapsed < 10s
    TEST_ASSERT_FALSE(BleRetryPolicy::shouldAttemptReconnect(2000, lastAttempt, 10000));
    // 7s after the wrap -> 10s elapsed, exact boundary
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldAttemptReconnect(7000, lastAttempt, 10000));
    // 11s after the wrap -> 14s elapsed
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldAttemptReconnect(11000, lastAttempt, 10000));
}

// --- isClientStale ---

void testStaleNoSuccessfulComm() {
    // 0 = no successful communication recorded, never stale
    TEST_ASSERT_FALSE(BleRetryPolicy::isClientStale(0, 0, 120000));
    TEST_ASSERT_FALSE(BleRetryPolicy::isClientStale(1000000, 0, 120000));
}

void testStaleWithinDeadline() {
    TEST_ASSERT_FALSE(BleRetryPolicy::isClientStale(100000, 100000, 120000));
    TEST_ASSERT_FALSE(BleRetryPolicy::isClientStale(220000, 100000, 120000));
}

void testStaleDeadlineExceeded() {
    // exact boundary is not yet stale (strictly greater than)
    TEST_ASSERT_FALSE(BleRetryPolicy::isClientStale(220000, 100000, 120000));
    TEST_ASSERT_TRUE(BleRetryPolicy::isClientStale(220001, 100000, 120000));
    TEST_ASSERT_TRUE(BleRetryPolicy::isClientStale(999999, 100000, 120000));
}

void testStaleAcrossWraparound() {
    const uint32_t lastOk = 0xFFFFFFFFu - 10000u + 1u;  // 10s before the wrap
    // 5s after the wrap -> 15s elapsed <= 20s deadline
    TEST_ASSERT_FALSE(BleRetryPolicy::isClientStale(5000, lastOk, 20000));
    // 10s after the wrap -> 20s elapsed, exact boundary
    TEST_ASSERT_FALSE(BleRetryPolicy::isClientStale(10000, lastOk, 20000));
    // 11s after the wrap -> 21s elapsed > 20s deadline
    TEST_ASSERT_TRUE(BleRetryPolicy::isClientStale(11000, lastOk, 20000));
}

// --- effectiveClientDeadlineMs ---

void testEffectiveDeadlineRtcValid() {
    // post-sync (RTC valid): the base deadline applies as-is
    TEST_ASSERT_EQUAL_UINT32(120000, BleRetryPolicy::effectiveClientDeadlineMs(true, 120000));
    TEST_ASSERT_EQUAL_UINT32(1, BleRetryPolicy::effectiveClientDeadlineMs(true, 1));
}

void testEffectiveDeadlineRtcInvalidTripled() {
    // pre-sync: payloads are never sent, so healthy cameras stay silent
    // and the deadline is tripled to avoid dropping them
    TEST_ASSERT_EQUAL_UINT32(360000, BleRetryPolicy::effectiveClientDeadlineMs(false, 120000));
    TEST_ASSERT_EQUAL_UINT32(0, BleRetryPolicy::effectiveClientDeadlineMs(false, 0));
}

// --- shouldRearmLivenessOnRtcEdge ---

void testRearmOnlyOnInvalidToValidEdge() {
    // the sync edge itself
    TEST_ASSERT_TRUE(BleRetryPolicy::shouldRearmLivenessOnRtcEdge(true, false));
    // valid -> invalid (should not happen, but must not re-arm either)
    TEST_ASSERT_FALSE(BleRetryPolicy::shouldRearmLivenessOnRtcEdge(false, true));
    // already valid on the previous pass
    TEST_ASSERT_FALSE(BleRetryPolicy::shouldRearmLivenessOnRtcEdge(true, true));
    // never valid
    TEST_ASSERT_FALSE(BleRetryPolicy::shouldRearmLivenessOnRtcEdge(false, false));
}

#ifdef ARDUINO
#include <Arduino.h>

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(testReconnectNoFailedAttempt);
    RUN_TEST(testReconnectWithinInterval);
    RUN_TEST(testReconnectIntervalElapsed);
    RUN_TEST(testReconnectAcrossWraparound);
    RUN_TEST(testStaleNoSuccessfulComm);
    RUN_TEST(testStaleWithinDeadline);
    RUN_TEST(testStaleDeadlineExceeded);
    RUN_TEST(testStaleAcrossWraparound);
    RUN_TEST(testEffectiveDeadlineRtcValid);
    RUN_TEST(testEffectiveDeadlineRtcInvalidTripled);
    RUN_TEST(testRearmOnlyOnInvalidToValidEdge);
    UNITY_END();
}

void loop() {
}

#else

int main() {
    UNITY_BEGIN();
    RUN_TEST(testReconnectNoFailedAttempt);
    RUN_TEST(testReconnectWithinInterval);
    RUN_TEST(testReconnectIntervalElapsed);
    RUN_TEST(testReconnectAcrossWraparound);
    RUN_TEST(testStaleNoSuccessfulComm);
    RUN_TEST(testStaleWithinDeadline);
    RUN_TEST(testStaleDeadlineExceeded);
    RUN_TEST(testStaleAcrossWraparound);
    RUN_TEST(testEffectiveDeadlineRtcValid);
    RUN_TEST(testEffectiveDeadlineRtcInvalidTripled);
    RUN_TEST(testRearmOnlyOnInvalidToValidEdge);
    UNITY_END();

    return 0;
}

#endif
