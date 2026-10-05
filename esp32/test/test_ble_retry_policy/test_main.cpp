#include <unity.h>

#include "BleRetryPolicy.h"

// --- CameraTiming: retry gate ---

void testReconnectNoFailedAttempt() {
    // no failed attempt on record: always allowed (also covers the first
    // interval after boot where millis() is still small)
    BleRetryPolicy::CameraTiming t;
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(0, 10000));
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(5000, 10000));
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(500000, 10000));
}

void testReconnectWithinInterval() {
    BleRetryPolicy::CameraTiming t;
    t.armRetryGate(1000);
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(5000, 10000));
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(10000, 10000));
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(10999, 10000));
}

void testReconnectIntervalElapsed() {
    // exact boundary counts as elapsed
    BleRetryPolicy::CameraTiming t;
    t.armRetryGate(1000);
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(11000, 10000));
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(999999, 10000));
}

void testReconnectAcrossWraparound() {
    // millis() wraps at 2^32 ms (~49.7 days); unsigned subtraction must
    // measure the true elapsed time across the wrap
    BleRetryPolicy::CameraTiming t;
    const uint32_t lastAttempt = 0xFFFFFFFFu - 3000u + 1u;  // 3s before the wrap
    t.armRetryGate(lastAttempt);
    // 2s after the wrap -> 5s elapsed < 10s
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(2000, 10000));
    // 7s after the wrap -> 10s elapsed, exact boundary
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(7000, 10000));
    // 11s after the wrap -> 14s elapsed
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(11000, 10000));
}

void testGateArmedAtExactRollover() {
    // a failed attempt recorded at millis() == 0 (the wraparound instant,
    // not just the first millisecond after boot) must keep the gate closed:
    // a 0-timestamp sentinel would misread it as "none on record" and
    // reopen the gate for one extra attempt
    BleRetryPolicy::CameraTiming t;
    t.armRetryGate(0);
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(1, 10000));
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(9999, 10000));
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(10000, 10000));
}

void testHandshakeSuccessClearsGate() {
    // a successful handshake clears an old failure, so the NEXT reconnect
    // after a later drop is not delayed by stale history
    BleRetryPolicy::CameraTiming t;
    t.armRetryGate(100000);
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(105000, 10000));
    t.clearRetryGate();
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(105001, 10000));
}

void testWriteFailureArmsGate() {
    // the M1 sequence: first attempt allowed, handshake succeeds (gate
    // cleared, liveness recorded), then a payload write fails and the
    // client is torn down — the teardown must arm the gate, so the
    // reconnect waits out the full interval instead of retrying on the
    // next advertisement
    BleRetryPolicy::CameraTiming t;
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(110000, 10000));
    t.clearRetryGate();
    t.recordCommOk(110000);
    // TIME write fails 30ms later; the worker drops the client and arms:
    t.armRetryGate(110030);
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(110031, 10000));
    TEST_ASSERT_FALSE(t.shouldAttemptReconnect(119999, 10000));
    TEST_ASSERT_TRUE(t.shouldAttemptReconnect(120030, 10000));
}

// --- CameraTiming: liveness ---

void testStaleNoSuccessfulComm() {
    // no successful communication recorded: never stale (handled by the
    // handshake failure path instead)
    BleRetryPolicy::CameraTiming t;
    TEST_ASSERT_FALSE(t.isStale(0, 120000));
    TEST_ASSERT_FALSE(t.isStale(1000000, 120000));
}

void testStaleWithinDeadline() {
    BleRetryPolicy::CameraTiming t;
    t.recordCommOk(100000);
    TEST_ASSERT_FALSE(t.isStale(100000, 120000));
    TEST_ASSERT_FALSE(t.isStale(220000, 120000));
}

void testStaleDeadlineExceeded() {
    // exact boundary is not yet stale (strictly greater than)
    BleRetryPolicy::CameraTiming t;
    t.recordCommOk(100000);
    TEST_ASSERT_FALSE(t.isStale(220000, 120000));
    TEST_ASSERT_TRUE(t.isStale(220001, 120000));
    TEST_ASSERT_TRUE(t.isStale(999999, 120000));
}

void testStaleAcrossWraparound() {
    BleRetryPolicy::CameraTiming t;
    const uint32_t lastOk = 0xFFFFFFFFu - 10000u + 1u;  // 10s before the wrap
    t.recordCommOk(lastOk);
    // 5s after the wrap -> 15s elapsed <= 20s deadline
    TEST_ASSERT_FALSE(t.isStale(5000, 20000));
    // 10s after the wrap -> 20s elapsed, exact boundary
    TEST_ASSERT_FALSE(t.isStale(10000, 20000));
    // 11s after the wrap -> 21s elapsed > 20s deadline
    TEST_ASSERT_TRUE(t.isStale(11000, 20000));
}

void testCommOkRecordedAtExactRollover() {
    // liveness recorded at millis() == 0 must still go stale after the
    // deadline: a 0-timestamp sentinel would keep such a client
    // unfreshable-stale until its next successful write
    BleRetryPolicy::CameraTiming t;
    t.recordCommOk(0);
    TEST_ASSERT_FALSE(t.isStale(5000, 120000));
    TEST_ASSERT_TRUE(t.isStale(120001, 120000));
}

void testRtcEdgeRearmRefreshesLiveness() {
    // on the invalid->valid RTC edge the worker re-arms every connected
    // client's liveness, so pre-sync silence is not held against them
    BleRetryPolicy::CameraTiming t;
    t.recordCommOk(1000);
    TEST_ASSERT_TRUE(t.isStale(400000, 120000));
    t.recordCommOk(400000);  // the worker's re-arm pass
    TEST_ASSERT_FALSE(t.isStale(400001, 120000));
}

// --- isBroadcastDue ---

void testBroadcastDue() {
    // 0 is the fresh-handshake / boot convention: due once millis() has
    // passed one interval (pre-existing worker behavior, kept)
    TEST_ASSERT_FALSE(BleRetryPolicy::isBroadcastDue(29999, 0, 30000));
    TEST_ASSERT_TRUE(BleRetryPolicy::isBroadcastDue(30000, 0, 30000));
    TEST_ASSERT_FALSE(BleRetryPolicy::isBroadcastDue(40000, 20000, 30000));
    TEST_ASSERT_TRUE(BleRetryPolicy::isBroadcastDue(50000, 20000, 30000));
}

void testBroadcastDueAcrossWraparound() {
    // 4s before the wrap -> 0.5s after it is 4.5s elapsed
    const uint32_t lastBroadcast = 0xFFFFFFFFu - 4000u + 1u;
    TEST_ASSERT_TRUE(BleRetryPolicy::isBroadcastDue(500, lastBroadcast, 4500));
    TEST_ASSERT_FALSE(BleRetryPolicy::isBroadcastDue(500, lastBroadcast, 4501));
}

void testDuePayloadServedBeforeStaleCheck() {
    // the M3 scenario: a healthy camera missed its due-check by 1ms, then
    // one pass spent ~148s on other cameras' blocked writes and a
    // handshake. At the next pass the same clock reading is BOTH due and
    // stale by the numbers — the worker serves the due payload first, so
    // the write refreshes liveness before the watchdog judges it. With the
    // old order (watchdog first), the healthy camera was destroyed here.
    BleRetryPolicy::CameraTiming camera;
    camera.recordCommOk(1000);
    TEST_ASSERT_TRUE(BleRetryPolicy::isBroadcastDue(149699, 1000, 30000));
    TEST_ASSERT_TRUE(camera.isStale(149699, 120000));  // stale by the numbers...
    camera.recordCommOk(149699);                       // ...but the due payload is served first
    TEST_ASSERT_FALSE(camera.isStale(149699, 120000));
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

// --- decideReconnect ---

void testDecideReconnectOrder() {
    // gate first: a camera inside its retry interval is skipped without
    // re-arming (the gate is already measuring)
    TEST_ASSERT_EQUAL((int)BleRetryPolicy::ReconnectDecision::SKIP_RETRY_GATE,  //
                      (int)BleRetryPolicy::decideReconnect(false, true, false));
    // pass cap second: a handshake already ran this pass — the result is
    // left queued for the next pass, no gate arming
    TEST_ASSERT_EQUAL((int)BleRetryPolicy::ReconnectDecision::SKIP_PASS_CAP,  //
                      (int)BleRetryPolicy::decideReconnect(true, true, false));
    TEST_ASSERT_EQUAL((int)BleRetryPolicy::ReconnectDecision::SKIP_PASS_CAP,  //
                      (int)BleRetryPolicy::decideReconnect(true, true, true));
    // slots last: skipped, and the caller arms the gate
    TEST_ASSERT_EQUAL((int)BleRetryPolicy::ReconnectDecision::SKIP_SLOTS_FULL,  //
                      (int)BleRetryPolicy::decideReconnect(true, false, false));
    TEST_ASSERT_EQUAL((int)BleRetryPolicy::ReconnectDecision::ATTEMPT_HANDSHAKE,  //
                      (int)BleRetryPolicy::decideReconnect(true, false, true));
}

// --- ScanDrainBudget ---

void testDrainStopsAfterHandshake() {
    // once a handshake ran this pass, no further results are taken — they
    // stay queued for the next pass instead of being discarded by the
    // one-handshake-per-pass cap
    BleRetryPolicy::ScanDrainBudget budget(10);
    TEST_ASSERT_TRUE(budget.canTakeNext(false));
    budget.onTaken();
    TEST_ASSERT_TRUE(budget.canTakeNext(false));
    TEST_ASSERT_FALSE(budget.canTakeNext(true));
}

void testDrainStopsAtResultCap() {
    // the hard cap keeps a continuously replenished queue from
    // monopolizing a pass; surplus results stay queued for the next pass
    BleRetryPolicy::ScanDrainBudget budget(3);
    budget.onTaken();
    budget.onTaken();
    budget.onTaken();
    TEST_ASSERT_FALSE(budget.canTakeNext(false));
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
    RUN_TEST(testGateArmedAtExactRollover);
    RUN_TEST(testHandshakeSuccessClearsGate);
    RUN_TEST(testWriteFailureArmsGate);
    RUN_TEST(testStaleNoSuccessfulComm);
    RUN_TEST(testStaleWithinDeadline);
    RUN_TEST(testStaleDeadlineExceeded);
    RUN_TEST(testStaleAcrossWraparound);
    RUN_TEST(testCommOkRecordedAtExactRollover);
    RUN_TEST(testRtcEdgeRearmRefreshesLiveness);
    RUN_TEST(testBroadcastDue);
    RUN_TEST(testBroadcastDueAcrossWraparound);
    RUN_TEST(testDuePayloadServedBeforeStaleCheck);
    RUN_TEST(testEffectiveDeadlineRtcValid);
    RUN_TEST(testEffectiveDeadlineRtcInvalidTripled);
    RUN_TEST(testRearmOnlyOnInvalidToValidEdge);
    RUN_TEST(testDecideReconnectOrder);
    RUN_TEST(testDrainStopsAfterHandshake);
    RUN_TEST(testDrainStopsAtResultCap);
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
    RUN_TEST(testGateArmedAtExactRollover);
    RUN_TEST(testHandshakeSuccessClearsGate);
    RUN_TEST(testWriteFailureArmsGate);
    RUN_TEST(testStaleNoSuccessfulComm);
    RUN_TEST(testStaleWithinDeadline);
    RUN_TEST(testStaleDeadlineExceeded);
    RUN_TEST(testStaleAcrossWraparound);
    RUN_TEST(testCommOkRecordedAtExactRollover);
    RUN_TEST(testRtcEdgeRearmRefreshesLiveness);
    RUN_TEST(testBroadcastDue);
    RUN_TEST(testBroadcastDueAcrossWraparound);
    RUN_TEST(testDuePayloadServedBeforeStaleCheck);
    RUN_TEST(testEffectiveDeadlineRtcValid);
    RUN_TEST(testEffectiveDeadlineRtcInvalidTripled);
    RUN_TEST(testRearmOnlyOnInvalidToValidEdge);
    RUN_TEST(testDecideReconnectOrder);
    RUN_TEST(testDrainStopsAfterHandshake);
    RUN_TEST(testDrainStopsAtResultCap);
    UNITY_END();

    return 0;
}

#endif
