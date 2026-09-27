#ifndef BLE_RETRY_POLICY_H
#define BLE_RETRY_POLICY_H

#include <stdint.h>

// Wrap-safe timing policy for BLE (re)connect attempts and stale-client
// detection, shared by the BleWorker task. Pure functions on millis()-style
// uint32_t timestamps so they can be unit-tested in the native environment.
//
// Convention (matching lastBroadcastMillis = 0 elsewhere in the worker):
// a timestamp of 0 means "none on record" — no failed reconnect attempt /
// no successful communication yet — and is always treated as the permissive
// case. A genuine timestamp of exactly 0 (millis() == 0, only possible in
// the first millisecond after boot — long before the worker can have any
// BLE state on record) collides with that sentinel and falls to the
// permissive side too, which is the safe direction: one extra retry or one
// delayed watchdog drop at worst.
namespace BleRetryPolicy {

// True when a reconnect attempt may be made now: either the camera has no
// failed attempt on record, or the fixed retry interval has elapsed since
// the last failed attempt (the worker arms the timestamp only after an
// attempt has actually finished — failed, or skipped entirely because all
// BLE slots were busy — so the interval is measured from the end of the
// attempt, not its start). Unsigned subtraction keeps this correct
// across the ~49.7-day millis() wraparound.
inline bool shouldAttemptReconnect(uint32_t nowMs, uint32_t lastAttemptMs, uint32_t retryIntervalMs) {
    if (lastAttemptMs == 0) return true;
    return nowMs - lastAttemptMs >= retryIntervalMs;
}

// True when a client that claims to be connected has gone longer than the
// deadline without any successful communication (handshake or payload write)
// and should be destroyed to release its BLE slot. A camera with no recorded
// success is never stale — it is handled by the handshake failure path.
inline bool isClientStale(uint32_t nowMs, uint32_t lastCommOkMs, uint32_t deadlineMs) {
    if (lastCommOkMs == 0) return false;
    return nowMs - lastCommOkMs > deadlineMs;
}

// Effective staleness deadline fed into isClientStale: the base deadline
// while the RTC is valid, tripled before the GNSS time sync lands —
// payloads are legitimately never sent then, so silence from a healthy
// connected camera is expected, and only handshakes refresh its liveness
// timestamp. A healthy camera merely re-handshakes when the tripled
// deadline cycles it; that is the price for recovering zombie slots even
// when the GNSS never syncs (e.g. indoors).
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

}  // namespace BleRetryPolicy

#endif  // BLE_RETRY_POLICY_H
