package info.skyblond.nsg

import java.util.*

object Const {
    /**
     * Primary service.
     * */
    @JvmStatic
    val NIKON_SERVICE_UUID = UUID.fromString("0000de00-3dd4-4255-8d62-6dc7b9bd5561")

    /**
     * Characteristic for writing pairing message and receive indications.
     * */
    @JvmStatic
    val PAIR_CHAR_UUID = UUID.fromString("00002000-3dd4-4255-8d62-6dc7b9bd5561")

    /**
     * Characteristic for success notification. After stage 4 message (cam to us),
     * the camera should emit `01 00` on this char.
     * */
    @JvmStatic
    val NOT1_CHAR_UUID = UUID.fromString("00002008-3dd4-4255-8d62-6dc7b9bd5561")
    @JvmStatic
    val NOT2_CHAR_UUID = UUID.fromString("0000200a-3dd4-4255-8d62-6dc7b9bd5561")

    /**
     * Characteristic for writing controller's id.
     * Should be 32 bytes of ASCII chars, padding with zero.
     * */
    @JvmStatic
    val ID_CHAR_UUID = UUID.fromString("00002002-3dd4-4255-8d62-6dc7b9bd5561")

    /**
     * Characteristic for writing GEO message, providing location to camera.
     * */
    @JvmStatic
    val GEO_CHAR_UUID = UUID.fromString("00002007-3dd4-4255-8d62-6dc7b9bd5561")

    /**
     * Characteristic for writing TIME message, providing time to camera.
     * */
    @JvmStatic
    val TIME_CHAR_UUID = UUID.fromString("00002006-3dd4-4255-8d62-6dc7b9bd5561")
}