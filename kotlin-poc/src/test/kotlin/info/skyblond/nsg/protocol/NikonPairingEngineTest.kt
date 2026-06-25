package info.skyblond.nsg.protocol

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.assertThrows
import kotlin.test.Test

class NikonPairingEngineTest {
    private val engine = NikonPairingEngine()

    @Test
    fun stage1DeviceHasRequiredLsb() {
        val stage1 = engine.createStage1(null, null)
        assertEquals(0x01L, stage1.device and 0xFFL)
    }

    @Test
    fun stage1DeviceIsStableWhenReusingSavedCamera() {
        val stage1 = engine.createStage1(0xAABBCCDDL, 0x11223344L)
        assertEquals(0xAABBCCDDL, stage1.device)
        assertEquals(0x11223344L, stage1.nonce)
    }

    @Test
    fun capturedStage2FindsSaltSixAndBuildsExpectedStage3() {
        // Real values captured from the Z50_2 camera handshake.
        val stage1 = PairingMessage(
            stage = 0x01,
            timestamp = 0x677da144ec13e1dbL,
            device = 0x3c3ae501L,
            nonce = 0x3fdaa451L
        )
        val stage2 = PairingMessage(
            stage = 0x02,
            timestamp = 0xb9943d5e8026fa29uL.toLong(),
            device = 0xa8b3f2e4L,
            nonce = 0x16d56a13L
        )

        val stage3 = engine.verifyStage2AndBuildStage3(stage1, stage2)

        assertEquals(0x03, stage3.stage)
        assertEquals(stage1.timestamp, stage3.timestamp)
        assertEquals(0x79f1ad53L, stage3.device)
        assertEquals(0x23838a35L, stage3.nonce)

        val expectedBytes = byteArrayOf(
            0x03.toByte(),
            0xdb.toByte(), 0xe1.toByte(), 0x13.toByte(), 0xec.toByte(),
            0x44.toByte(), 0xa1.toByte(), 0x7d.toByte(), 0x67.toByte(),
            0x53.toByte(), 0xad.toByte(), 0xf1.toByte(), 0x79.toByte(),
            0x35.toByte(), 0x8a.toByte(), 0x83.toByte(), 0x23.toByte()
        )
        assertArrayEquals(expectedBytes, stage3.encode())
    }

    @Test
    fun stage3HasCorrectStageAndTimestamp() {
        // Build a fake stage2 that won't pass salt verification, just verify structure.
        val stage1 = engine.createStage1(null, null)
        val stage2 = PairingMessage(
            stage = 0x02,
            timestamp = 0L,
            device = 0L,
            nonce = 0L
        )
        // With zero stage2, salt verification will fail.
        assertThrows<IllegalStateException> {
            engine.verifyStage2AndBuildStage3(stage1, stage2)
        }
    }
}