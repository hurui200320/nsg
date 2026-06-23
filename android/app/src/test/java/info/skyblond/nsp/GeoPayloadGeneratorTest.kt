package info.skyblond.nsp.ble

import org.junit.Assert.assertEquals
import org.junit.Test

class GeoPayloadGeneratorTest {

    @Test
    fun generatedPayloadIs41Bytes() {
        val payload = GeoPayloadGenerator.buildFake()
        assertEquals(41, payload.size)
    }

    @Test
    fun headerIsCorrect() {
        val payload = GeoPayloadGenerator.buildFake()
        // 0x007F little-endian: first byte 0x7F, second byte 0x00
        assertEquals(0x7F.toByte(), payload[0])
        assertEquals(0x00.toByte(), payload[1])
    }

    @Test
    fun standardFieldIsWgs84() {
        val payload = GeoPayloadGenerator.buildFake()
        val standard = payload.copyOfRange(25, 31).toString(Charsets.US_ASCII)
        assertEquals("WGS-84", standard)
    }
}
