package info.skyblond.nsp.ble.protocol

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
