package info.skyblond.nsg.protocol

import org.junit.jupiter.api.Assertions.*
import kotlin.test.Test

class BlowfishHasherTest {
    @Suppress("REDUNDANT_CALL_OF_CONVERSION_METHOD")
    @Test
    fun capturedCameraHashMatchesFurble() {
        // Hash input for SALT 6 with the captured stage1/stage2 handshake values.
        // SALT[6] = {0xcd32687f, 0xa9e28a30}
        // stage2 timestamp low/high (bswap): 0x29fa2680, 0x5e3d94b9
        // stage1 timestamp low/high (bswap): 0xdbe113ec, 0x44a17d67
        val blocks = intArrayOf(
            0xcd32687f.toInt(), 0xa9e28a30.toInt(),
            0x29fa2680.toInt(), 0x5e3d94b9.toInt(),
            0xdbe113ec.toInt(), 0x44a17d67.toInt()
        )
        val (h0, h1) = BlowfishHasher().hash(blocks)
        assertEquals(0xe4f2b3a8.toInt(), h0)
        assertEquals(0x136ad516.toInt(), h1)
    }
}