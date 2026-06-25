package info.skyblond.nsg.protocol

import org.junit.jupiter.api.Assertions.assertEquals
import kotlin.test.Test
import kotlin.test.assertContentEquals

class PairingMessageTest {
    @Test
    fun encodeDecodeRoundTrip() {
        val original = PairingMessage(
            stage = 0x03,
            timestamp = 0x123456789ABCDEF0L,
            device = 0xAABBCCDDL,
            nonce = 0x11223344L
        )
        val encoded = original.encode()
        assertEquals(17, encoded.size)

        // check bytes content
        assertContentEquals(
            byteArrayOf(
                // stage
                0x03.toByte(),
                // timestamp in small endian
                0xf0.toByte(), 0xde.toByte(), 0xbc.toByte(), 0x9a.toByte(),
                0x78.toByte(), 0x56.toByte(), 0x34.toByte(), 0x12.toByte(),
                // device in small endian
                0xdd.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0xaa.toByte(),
                // nonce in small endian
                0x44.toByte(), 0x33.toByte(), 0x22.toByte(), 0x11.toByte()
            ),
            encoded
        )

        val decoded = PairingMessage.decode(encoded)
        assertEquals(original.stage, decoded.stage)
        assertEquals(original.timestamp, decoded.timestamp)
        assertEquals(original.device, decoded.device)
        assertEquals(original.nonce, decoded.nonce)
    }
}