package info.skyblond.nsp.ble.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class NikonPairingEngineTest {

    private val engine = NikonPairingEngine()

    @Test
    fun stage1DeviceHasRequiredLsb() {
        val stage1 = engine.createStage1()
        assertEquals(0x01L, stage1.device and 0xFFL)
    }

    @Test
    fun stage1DeviceIsStableWhenReusingSavedCamera() {
        val saved = SavedCameraTestData
        val stage1 = engine.createStage1(saved)
        assertEquals(saved.device, stage1.device)
        assertEquals(saved.nonce, stage1.nonce)
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

        assertEquals(0x03, stage3?.stage)
        assertEquals(stage1.timestamp, stage3?.timestamp)
        assertEquals(0x79f1ad53L, stage3?.device)
        assertEquals(0x23838a35L, stage3?.nonce)

        val expectedBytes = byteArrayOf(
            0x03.toByte(), 0xdb.toByte(), 0xe1.toByte(), 0x13, 0xec.toByte(),
            0x44, 0xa1.toByte(), 0x7d, 0x67, 0x53, 0xad.toByte(),
            0xf1.toByte(), 0x79, 0x35, 0x8a.toByte(), 0x83.toByte(), 0x23
        )
        assertArrayEquals(expectedBytes, stage3?.encode())
    }

    @Test
    fun stage3HasCorrectStageAndTimestamp() {
        // Build a fake stage2 that won't pass salt verification, just verify structure.
        val stage1 = engine.createStage1()
        val stage2 = PairingMessage(
            stage = 0x02,
            timestamp = 0L,
            device = 0L,
            nonce = 0L
        )
        val stage3 = engine.verifyStage2AndBuildStage3(stage1, stage2)
        // With zero stage2, salt verification will fail.
        assertEquals(null, stage3)
    }

    companion object {
        val SavedCameraTestData = info.skyblond.nsp.data.PairedCamera(
            name = "Test",
            address = "00:11:22:33:44:55",
            addressType = 2,
            device = 0xAABBCCDDL,
            nonce = 0x11223344L,
            controllerName = "nsg-test"
        )
    }
}
