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

}
