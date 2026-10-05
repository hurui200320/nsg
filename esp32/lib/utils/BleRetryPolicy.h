#ifndef BLE_RETRY_POLICY_H
#define BLE_RETRY_POLICY_H

#include <stdint.h>

// Wrap-safe timing and retry policy for the BleWorker task: pure functions
// and small state holders on millis()-style uint32_t timestamps, so they can
// be unit-tested in the native environment.
//
// Recorded timestamps use explicit "has*" booleans instead of a
// 0-timestamp sentinel: millis() == 0 also occurs at the ~49.7-day
// wraparound, and a record landing exactly there would be misread as
// "none on record" — reopening the retry gate for one extra attempt or
// keeping a client unfreshable-stale until its next write. With the
// booleans, a record at ms 0 is honored like any other timestamp, and
// unsigned subtraction keeps every elapsed-time comparison correct across
// the wrap.
//
// The one remaining 0-convention, lastBroadcastMillis == 0 (the field's
// boot value, and the value the worker stores on a fresh handshake: "due
// as soon as millis() has passed one interval"), is pre-existing and
// benign — at worst one payload is sent an interval late right after boot.
namespace BleRetryPolicy {

// Per-camera retry-gate and liveness bookkeeping. Owned and written only by
// the worker task (one instance per ConnectedCamera).
struct CameraTiming {
    // millis() of the last FAILED reconnect/handshake attempt — including
    // one skipped entirely because all BLE slots were busy, and one armed
    // when a failed payload write tore the client down. hasAttempt = false
    // means none on record.
    uint32_t lastAttemptMs = 0;
    bool hasAttempt = false;

    // millis() of the last successful handshake or TIME/GEO write.
    // hasCommOk = false means none on record.
    uint32_t lastCommOkMs = 0;
    bool hasCommOk = false;

    // Arm the retry gate: no reconnect attempt until
    // shouldAttemptReconnect() reopens it. Armed when an attempt finishes
    // (failed, or skipped for full slots) or when a payload write fails and
    // the client is torn down — always measured from the END of the failed
    // attempt, so a slow ~45s attempt still yields a full interval of rest.
    void armRetryGate(uint32_t nowMs) {
        lastAttemptMs = nowMs;
        hasAttempt = true;
    }

    // A successful handshake clears the gate: the camera is connected and
    // communicating, so an old failure must not delay its NEXT reconnect
    // after a later drop.
    void clearRetryGate() { hasAttempt = false; }

    // A successful handshake or TIME/GEO write refreshes liveness. Also
    // used to re-arm every connected client's liveness on the
    // invalid->valid RTC edge (see shouldRearmLivenessOnRtcEdge).
    void recordCommOk(uint32_t nowMs) {
        lastCommOkMs = nowMs;
        hasCommOk = true;
    }

    // True when a reconnect attempt may be made now: either the camera has
    // no failed attempt on record, or the retry interval has elapsed since
    // the last one.
    bool shouldAttemptReconnect(uint32_t nowMs, uint32_t retryIntervalMs) const {
        if (!hasAttempt) return true;
        return nowMs - lastAttemptMs >= retryIntervalMs;
    }

    // True when a client that claims to be connected has gone longer than
    // the deadline without any successful communication and should be
    // destroyed to release its BLE slot. A camera with no recorded success
    // is never stale — it is handled by the handshake failure path.
    bool isStale(uint32_t nowMs, uint32_t deadlineMs) const {
        if (!hasCommOk) return false;
        return nowMs - lastCommOkMs > deadlineMs;
    }
};

// True when the camera's TIME/GEO broadcast is due. Exactly the expression
// the worker used inline (including the fresh-handshake
// lastBroadcastMillis == 0 convention noted above), extracted so the
// due-check semantics are covered by the native tests.
inline bool isBroadcastDue(uint32_t nowMs, uint32_t lastBroadcastMs, uint32_t intervalMs) {
    return nowMs - lastBroadcastMs >= intervalMs;
}

// Effective staleness deadline fed into CameraTiming::isStale: the base
// deadline while the RTC is valid, tripled before the GNSS time sync
// lands — payloads are legitimately never sent then, so silence from a
// healthy connected camera is expected, and only handshakes refresh its
// liveness timestamp. A healthy camera merely re-handshakes when the
// tripled deadline cycles it; that is the price for recovering zombie
// slots even when the GNSS never syncs (e.g. indoors).
inline uint32_t effectiveClientDeadlineMs(bool rtcValid, uint32_t baseDeadlineMs) {
    return rtcValid ? baseDeadlineMs : 3u * baseDeadlineMs;
}

// True exactly on the invalid->valid RTC edge: the deadline's meaning
// changes there (silence from a connected camera stops being expected), so
// liveness timestamps gathered pre-sync must be re-armed to keep a slow
// GNSS cold start from dropping healthy cameras the moment the clock syncs.
inline bool shouldRearmLivenessOnRtcEdge(bool rtcValid, bool rtcWasValid) {
    return rtcValid && !rtcWasValid;
}

// What the worker should do about a scan result for a camera that has no
// client, in decision order — the order matters:
//  - the retry gate comes first: a camera inside its backoff is skipped
//    WITHOUT re-arming (the gate is already measuring; re-arming on every
//    advertisement would turn it into a sliding window that never reopens);
//  - the one-handshake-per-pass cap comes next: the result is left queued
//    for the next pass (see ScanDrainBudget) instead of being discarded;
//  - the free-slot count last: a skipped attempt is still a failed
//    attempt, so the caller arms the gate and the "slots full" warning is
//    reconsidered at most once per retry interval.
enum class ReconnectDecision {
    SKIP_RETRY_GATE,   // too soon since this camera's last failed attempt
    SKIP_PASS_CAP,     // another handshake already ran this pass
    SKIP_SLOTS_FULL,   // all BLE slots busy; caller arms the retry gate
    ATTEMPT_HANDSHAKE  // create a client and connect
};
inline ReconnectDecision decideReconnect(bool retryGateOpen, bool handshakeAttemptedThisPass, bool slotsAvailable) {
    if (!retryGateOpen) return ReconnectDecision::SKIP_RETRY_GATE;
    if (handshakeAttemptedThisPass) return ReconnectDecision::SKIP_PASS_CAP;
    if (!slotsAvailable) return ReconnectDecision::SKIP_SLOTS_FULL;
    return ReconnectDecision::ATTEMPT_HANDSHAKE;
}

// Per-pass budget for consuming scanner-queue results. Two bounds:
//  - stops after the pass's first handshake attempt: a handshake can block
//    the worker for up to ~45-60s, and any result dequeued afterwards would
//    only be discarded by the one-handshake-per-pass cap — leaving it
//    queued preserves it for the next pass (<=1s away), so an
//    intermittently advertising camera is not lost (issue #25);
//  - a hard cap on results per pass so a continuously replenished queue
//    cannot monopolize the pass; surplus results stay queued (the scanner
//    queue is sized to hold them) and are handled by the next pass.
class ScanDrainBudget {
   public:
    explicit ScanDrainBudget(uint32_t maxResults) : maxResults(maxResults) {}

    // True while this pass may take another scan result from the queue.
    bool canTakeNext(bool handshakeAttempted) const {
        return taken < maxResults && !handshakeAttempted;
    }

    // Record that one more result was taken (and will be processed).
    void onTaken() { ++taken; }

   private:
    const uint32_t maxResults;
    uint32_t taken = 0;
};

}  // namespace BleRetryPolicy

#endif  // BLE_RETRY_POLICY_H
