package info.skyblond.nsp.ble.protocol

import org.junit.Assert.assertEquals
import org.junit.Test

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

        val decoded = PairingMessage.decode(encoded)
        assertEquals(original.stage, decoded.stage)
        assertEquals(original.timestamp, decoded.timestamp)
        assertEquals(original.device, decoded.device)
        assertEquals(original.nonce, decoded.nonce)
    }

    @Test
    fun stage5Encoding() {
        val stage5 = PairingMessage(stage = 0x05, timestamp = 0L, device = 0L, nonce = 0L)
        val encoded = stage5.encode()
        assertEquals(17, encoded.size)
        assertEquals(0x05.toByte(), encoded[0])
        encoded.copyOfRange(1, 17).forEach { byte ->
            assertEquals(0x00.toByte(), byte)
        }
    }
}
