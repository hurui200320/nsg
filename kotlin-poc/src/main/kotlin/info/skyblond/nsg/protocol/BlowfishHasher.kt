package info.skyblond.nsp.ble.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

/**
 * Implements the custom Blowfish-based hash used in the Nikon pairing handshake.
 *
 * The underlying block cipher is standard Blowfish in ECB mode with no padding.
 * The 8-byte key is:
 *     FF FF AA 55 11 22 33 00
 *
 * Hash input blocks are treated as big-endian 32-bit words.
 */
class BlowfishHasher {

    private val cipher: Cipher = Cipher.getInstance("Blowfish/ECB/NoPadding").apply {
        init(Cipher.ENCRYPT_MODE, SecretKeySpec(KEY, "Blowfish"))
    }

    /**
     * [blocks] must contain an even number of 32-bit big-endian words.
     * Returns the final (left, right) pair.
     */
    fun hash(blocks: IntArray): Pair<Int, Int> {
        require(blocks.size % 2 == 0) { "blocks length must be even" }

        var left = 0x01020304
        var right = 0x05060708

        for (i in blocks.indices step 2) {
            val inL = blocks[i] xor left
            val inR = blocks[i + 1] xor right
            val enc = encryptBlock(inL, inR)
            left = enc.first
            right = enc.second
        }

        return left to right
    }

    private fun encryptBlock(left: Int, right: Int): Pair<Int, Int> {
        val input = ByteBuffer.allocate(8)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(left)
            .putInt(right)
            .array()

        val output = cipher.update(input)
            ?: throw IllegalStateException("Blowfish encryption failed")

        val buffer = ByteBuffer.wrap(output).order(ByteOrder.BIG_ENDIAN)
        return buffer.getInt() to buffer.getInt()
    }

    companion object {
        private val KEY = byteArrayOf(
            0xFF.toByte(), 0xFF.toByte(), 0xAA.toByte(), 0x55.toByte(),
            0x11.toByte(), 0x22.toByte(), 0x33.toByte(), 0x00.toByte()
        )
    }
}
