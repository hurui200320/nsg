package info.skyblond.nsg.protocol

import org.junit.jupiter.api.Assertions.*
import kotlin.test.Test

class GeoPayloadGeneratorTest {
    @Test
    fun generatedPayloadIs41Bytes() {
        val payload = GeoPayloadGenerator.buildPackage(
            12.1, 32.2, 400, 13,
        )
        assertEquals(41, payload.size)
    }

    @Test
    fun headerIsCorrect() {
        val payload = GeoPayloadGenerator.buildPackage(
            12.1, 32.2, 400, 13,
        )
        // 0x007F little-endian: first byte 0x7F, second byte 0x00
        assertEquals(0x7F.toByte(), payload[0])
        assertEquals(0x00.toByte(), payload[1])
    }

    @Test
    fun standardFieldIsWgs84() {
        val payload = GeoPayloadGenerator.buildPackage(
            12.1, 32.2, 400, 13,
        )
        val standard = payload.copyOfRange(25, 31).toString(Charsets.US_ASCII)
        assertEquals("WGS-84", standard)
    }
}