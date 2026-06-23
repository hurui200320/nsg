package info.skyblond.nsp.ble.protocol

import info.skyblond.nsp.data.PairedCamera
import java.security.SecureRandom

/**
 * Drives the 4-stage Nikon smart-device pairing handshake.
 *
 * Pair mode generates fresh [device] and [nonce]; reconnect mode reuses the values
 * stored in a [PairedCamera]. The timestamp is always freshly generated.
 */
class NikonPairingEngine(
    private val hasher: BlowfishHasher = BlowfishHasher()
) {

    private val random = SecureRandom()

    /**
     * Build stage 1. If [saved] is provided, its device/nonce are reused.
     */
    fun createStage1(saved: PairedCamera? = null): PairingMessage {
        val timestamp = random.nextLong()
        val device = saved?.device ?: generateDeviceId()
        val nonce = saved?.nonce ?: generateNonce()
        return PairingMessage(stage = 0x01, timestamp = timestamp, device = device, nonce = nonce)
    }

    /**
     * Verify the camera's stage-2 challenge, find the matching salt, and build
     * the stage-3 response. Returns null if no salt matches.
     */
    fun verifyStage2AndBuildStage3(
        stage1: PairingMessage,
        stage2: PairingMessage
    ): PairingMessage? {
        val salt = findSalt(stage1, stage2) ?: return null

        val (ourLo, ourHi) = timestampHalvesBe(stage1.timestamp)
        val (camLo, camHi) = timestampHalvesBe(stage2.timestamp)

        val blocks = intArrayOf(
            SALTS[salt][0], SALTS[salt][1],
            ourLo, ourHi,
            camLo, camHi
        )
        val (r0, r1) = hasher.hash(blocks)
        return PairingMessage(
            stage = 0x03,
            timestamp = stage1.timestamp,
            device = Integer.reverseBytes(r0).toLong() and 0xFFFFFFFFL,
            nonce = Integer.reverseBytes(r1).toLong() and 0xFFFFFFFFL
        )
    }

    /**
     * Extract the 8-byte ASCII camera serial number from stage 4.
     */
    fun extractSerial(stage4: PairingMessage): String {
        return stage4.encode()
            .copyOfRange(9, 17)
            .toString(Charsets.US_ASCII)
    }

    private fun generateDeviceId(): Long {
        // First byte on the wire must be 0x01. On a little-endian uint32 that means the LSB.
        val rnd = random.nextInt().toLong() and 0xFFFFFFFFL
        return (rnd and 0xFFFFFF00L) or 0x01L
    }

    private fun generateNonce(): Long {
        return random.nextInt().toLong() and 0xFFFFFFFFL
    }

    private fun findSalt(stage1: PairingMessage, stage2: PairingMessage): Int? {
        val (camLo, camHi) = timestampHalvesBe(stage2.timestamp)
        val (ourLo, ourHi) = timestampHalvesBe(stage1.timestamp)
        val camDevice = (stage2.device and 0xFFFFFFFFL).toInt()
        val camNonce = (stage2.nonce and 0xFFFFFFFFL).toInt()
        val camDeviceBe = Integer.reverseBytes(camDevice)
        val camNonceBe = Integer.reverseBytes(camNonce)

        for (i in SALTS.indices) {
            val blocks = intArrayOf(
                SALTS[i][0], SALTS[i][1],
                camLo, camHi,
                ourLo, ourHi
            )
            val (h0, h1) = hasher.hash(blocks)
            if (h0 == camDeviceBe && h1 == camNonceBe) {
                return i
            }
        }
        return null
    }

    private fun timestampHalvesBe(timestamp: Long): Pair<Int, Int> {
        val lo = (timestamp and 0xFFFFFFFFL).toInt()
        val hi = ((timestamp ushr 32) and 0xFFFFFFFFL).toInt()
        return Integer.reverseBytes(lo) to Integer.reverseBytes(hi)
    }

    companion object {
        private val SALTS = arrayOf(
            intArrayOf(0x704066e4.toInt(), 0x0433d552.toInt()),
            intArrayOf(0xed4b8fac.toInt(), 0x15f7e47b.toInt()),
            intArrayOf(0x24471f11.toInt(), 0x8b5ea1fc.toInt()),
            intArrayOf(0x05960c31.toInt(), 0x2b8c7f41.toInt()),
            intArrayOf(0xfda588c1.toInt(), 0xeba8b1f3.toInt()),
            intArrayOf(0x99166056.toInt(), 0x1bd3d550.toInt()),
            intArrayOf(0xcd32687f.toInt(), 0xa9e28a30.toInt()),
            intArrayOf(0x2a8fe834.toInt(), 0xdec7ebf4.toInt())
        )
    }
}
